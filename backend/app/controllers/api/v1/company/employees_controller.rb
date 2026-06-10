# frozen_string_literal: true

module Api
  module V1
    module Company
      class EmployeesController < BaseController
        def index
          employees = policy_scope(Employee).order(created_at: :desc)
          render json: { employees: employees.map { |e| employee_json(e, include_nudge: true) } }
        end

        def show
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :show?
          active_code = employee.employee_access_codes.active.first
          latest_invitation = employee.employee_invitations.order(created_at: :desc).first

          render json: {
            employee: employee_json(employee, include_nudge: true).merge(
              active_access_code_hint: active_code&.code_hint_last_two,
              invitation_status: latest_invitation&.delivery_status
            )
          }
        end

        def create
          authorize Employee, :create?
          result = InviteEmployeeService.call(
            company: current_company,
            phone_e164: params[:phone_e164],
            display_name: params[:display_name],
            department: params[:department],
            invited_by: current_company_user,
            send_whatsapp: params[:send_whatsapp] != false
          )

          render json: {
            employee: employee_json(result[:employee]),
            access_code: result[:access_code],
            invitation_id: result[:invitation].id
          }, status: :created
        end

        def bulk_create
          authorize Employee, :create?
          created = []
          batch_id = SecureRandom.uuid

          Array(params[:employees]).each do |row|
            result = InviteEmployeeService.call(
              company: current_company,
              phone_e164: row[:phone_e164] || row["phone_e164"],
              display_name: row[:display_name] || row["display_name"],
              department: row[:department] || row["department"],
              invited_by: current_company_user
            )
            result[:invitation].update!(batch_id: batch_id)
            created << employee_json(result[:employee]).merge(
              access_code: result[:access_code],
              invitation_id: result[:invitation].id
            )
          end

          render json: { employees: created, batch_id: batch_id }, status: :created
        end

        def update_phone
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :update_phone?
          result = Employees::UpdatePhoneService.call(
            employee: employee,
            new_phone_e164: params[:phone_e164],
            changed_by: current_company_user
          )

          render json: {
            employee: employee_json(result[:employee]),
            access_code: result[:access_code]
          }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def nudge
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :nudge?

          response = nil
          employee.with_lock do
            employee.reload

            if employee.participation_status == "completed"
              response = { status: :unprocessable_entity, json: { error: "Employee already completed" } }
              next
            end

            if nudge_cooldown_active?(employee)
              hours_left = nudge_cooldown_hours_remaining(employee)
              response = {
                status: :too_many_requests,
                json: { error: "Nudge cooldown active", retry_after_hours: hours_left.ceil }
              }
              next
            end

            employee.update!(last_nudged_at: Time.current)
            SendEmployeeNudgeJob.perform_later(employee.id, current_company_user.id)
            response = { status: :ok, json: { ok: true, message: "Nudge queued" } }
          end

          render json: response[:json], status: response[:status]
        end

        private

        def employee_json(employee, include_nudge: false)
          json = {
            id: employee.id,
            phone_e164: employee.phone_e164,
            display_name: employee.display_name,
            department: employee.department,
            role_title: employee.role_title,
            seniority: employee.seniority,
            profile: employee.profile_data,
            participation_status: employee.participation_status,
            onboarding_step: employee.onboarding_step,
            preferred_language: employee.preferred_language,
            invited_at: employee.invited_at,
            started_at: employee.started_at,
            completed_at: employee.completed_at,
            last_active_at: employee.last_active_at,
            last_nudged_at: employee.last_nudged_at,
            consent_given_at: employee.consent_given_at
          }

          if include_nudge
            json[:can_nudge] = can_nudge?(employee)
            json[:stalled] = stalled?(employee)
          end

          json
        end

        def can_nudge?(employee)
          employee.participation_status == "started" && !nudge_cooldown_active?(employee)
        end

        def nudge_cooldown_active?(employee)
          employee.last_nudged_at.present? &&
            employee.last_nudged_at > SendEmployeeNudgeJob::NUDGE_COOLDOWN.ago
        end

        def nudge_cooldown_hours_remaining(employee)
          ((employee.last_nudged_at + SendEmployeeNudgeJob::NUDGE_COOLDOWN) - Time.current) / 1.hour
        end

        def stalled?(employee)
          employee.participation_status == "started" &&
            employee.last_active_at.present? &&
            employee.last_active_at < 48.hours.ago
        end
      end
    end
  end
end
