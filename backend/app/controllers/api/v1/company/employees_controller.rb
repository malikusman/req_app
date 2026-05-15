# frozen_string_literal: true

module Api
  module V1
    module Company
      class EmployeesController < BaseController
        before_action :require_company_admin!, except: %i[index show]

        def index
          employees = company_scope(Employee).order(created_at: :desc)
          render json: { employees: employees.map { |e| employee_json(e, include_nudge: true) } }
        end

        def show
          employee = company_scope(Employee).find(params[:id])
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
          employee = company_scope(Employee).find(params[:id])
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
          employee = company_scope(Employee).find(params[:id])

          if employee.participation_status == "completed"
            return render json: { error: "Employee already completed" }, status: :unprocessable_entity
          end

          if employee.last_nudged_at.present? && employee.last_nudged_at > 24.hours.ago
            hours_left = ((employee.last_nudged_at + 24.hours) - Time.current) / 1.hour
            return render json: {
              error: "Nudge cooldown active",
              retry_after_hours: hours_left.ceil
            }, status: :too_many_requests
          end

          SendEmployeeNudgeJob.perform_later(employee.id, current_company_user.id)

          render json: { ok: true, message: "Nudge queued" }
        end

        private

        def require_company_admin!
          render json: { error: "Forbidden" }, status: :forbidden unless current_company_user.company_admin?
        end

        def employee_json(employee, include_nudge: false)
          json = {
            id: employee.id,
            phone_e164: employee.phone_e164,
            display_name: employee.display_name,
            department: employee.department,
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
          employee.participation_status == "started" &&
            (employee.last_nudged_at.blank? || employee.last_nudged_at <= 24.hours.ago)
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
