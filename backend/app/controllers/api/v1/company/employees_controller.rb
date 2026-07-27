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
              invitation_status: latest_invitation&.delivery_status,
              recent_nudges: recent_nudges_json(employee)
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
            email: params[:email],
            invited_by: current_company_user,
            send_whatsapp: params[:send_whatsapp] != false,
            preferred_channel: params[:preferred_channel].presence || "whatsapp"
          )

          render json: {
            employee: employee_json(result[:employee]),
            access_code: result[:access_code],
            invitation_id: result[:invitation].id,
            discover_url: result[:discover_url]
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
              email: row[:email] || row["email"],
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

        def reissue_access_code
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :reissue_access_code?
          _record, plain = EmployeeAccessCode.issue_for!(
            employee: employee,
            issued_by_type: "admin_reissue"
          )

          render json: {
            employee: employee_json(employee.reload, include_nudge: true),
            access_code: plain
          }
        end

        def nudge
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :nudge?

          result = Employees::NudgeService.call(employee: employee, company_user: current_company_user)

          render json: {
            ok: true,
            message: result.message,
            nudge: nudge_json(result.nudge)
          }
        rescue Employees::NudgeService::CooldownError => e
          render json: {
            error: e.message,
            retry_after_hours: e.retry_after_hours.ceil
          }, status: :too_many_requests
        rescue Employees::NudgeService::NudgeError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def employee_json(employee, include_nudge: false)
          active_code = employee.employee_access_codes.active.order(created_at: :desc).first
          json = {
            id: employee.id,
            phone_e164: employee.phone_e164,
            email: employee.email,
            preferred_channel: employee.preferred_channel,
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
            consent_given_at: employee.consent_given_at,
            access_code: active_code&.code_plaintext,
            access_code_hint: active_code&.code_hint_last_two,
            access_code_expires_at: active_code&.expires_at
          }

          if include_nudge
            json[:can_nudge] = can_nudge?(employee)
            json[:stalled] = stalled?(employee)
            latest = employee.employee_nudges.order(sent_at: :desc).first
            json[:latest_nudge] = latest ? nudge_json(latest) : nil
          end

          json
        end

        def nudge_json(nudge)
          {
            id: nudge.id,
            channel: nudge.channel,
            delivery_status: nudge.delivery_status,
            whatsapp_status: nudge.whatsapp_status,
            email_status: nudge.email_status,
            error_message: nudge.error_message,
            sent_at: nudge.sent_at
          }
        end

        def recent_nudges_json(employee)
          employee.employee_nudges.order(sent_at: :desc).limit(5).map { |n| nudge_json(n) }
        end

        def can_nudge?(employee)
          Employees::NudgeEligibility.can_nudge?(employee)
        end

        def stalled?(employee)
          employee.participation_status == "started" && employee.last_active_at.present? &&
            employee.last_active_at < 48.hours.ago
        end
      end
    end
  end
end
