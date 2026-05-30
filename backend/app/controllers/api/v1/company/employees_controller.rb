# frozen_string_literal: true

module Api
  module V1
    module Company
      class EmployeesController < BaseController
        skip_before_action :require_active_subscription!

        def index
          current_company.ensure_join_code!
          employees = policy_scope(Employee).order(created_at: :desc)
          render json: {
            company_join_code: current_company.join_code,
            employees: employees.map { |e| employee_json(e, include_nudge: true) }
          }
        end

        def show
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :show?
          latest_invitation = employee.employee_invitations.order(created_at: :desc).first

          render json: {
            employee: employee_json(employee, include_nudge: true).merge(
              invitation_status: latest_invitation&.delivery_status
            )
          }
        end

        def create
          authorize Employee, :create?
          result = InviteEmployeeService.call(
            company: current_company,
            phone_e164: params[:phone_e164],
            email: params[:email],
            display_name: params[:display_name],
            department: params[:department],
            invited_by: current_company_user,
            send_whatsapp: params[:send_whatsapp] != false
          )

          render json: {
            employee: employee_json(result[:employee]),
            company_join_code: result[:company_join_code],
            invitation_id: result[:invitation].id
          }, status: :created
        end

        def bulk_create
          authorize Employee, :create?
          created = []
          batch_id = SecureRandom.uuid
          rows = if params[:file].respond_to?(:read)
                   Employees::BulkInviteParser.call(file: params[:file])
                 else
                   Array(params[:employees])
                 end

          rows.each do |row|
            result = InviteEmployeeService.call(
              company: current_company,
              phone_e164: row[:phone_e164] || row["phone_e164"],
              email: row[:email] || row["email"],
              display_name: row[:display_name] || row["display_name"],
              department: row[:department] || row["department"],
              invited_by: current_company_user
            )
            result[:invitation].update!(batch_id: batch_id)
            created << employee_json(result[:employee]).merge(
              company_join_code: result[:company_join_code],
              invitation_id: result[:invitation].id
            )
          end

          render json: {
            employees: created,
            batch_id: batch_id,
            company_join_code: current_company.join_code
          }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
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
            company_join_code: result[:company_join_code]
          }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def nudge
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :nudge?

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

        def employee_json(employee, include_nudge: false)
          json = {
            id: employee.id,
            phone_e164: employee.phone_e164,
            email: employee.email,
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
