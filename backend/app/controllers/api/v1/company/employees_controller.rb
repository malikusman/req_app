# frozen_string_literal: true

module Api
  module V1
    module Company
      class EmployeesController < BaseController
        # Staff are invited once the Stage 1 price is accepted; someone beyond it
        # needs the client to confirm the extra charge (Doc 14 §4.1, Doc 17 §12).
        rescue_from Engagements::StaffInvitations::NotYetAllowed do |e|
          render json: { code: "invitations_locked", error: e.message }, status: :conflict
        end
        rescue_from Engagements::StaffInvitations::ConfirmationRequired do |e|
          render json: e.details.merge(error: e.message), status: :conflict
        end

        def index
          employees = policy_scope(Employee).order(created_at: :desc)
          render json: { employees: employees.map { |e| employee_json(e, include_nudge: true) },
                         invitations: Engagements::StaffInvitations.new(current_company).summary }
        end

        def show
          employee = policy_scope(Employee).find(params[:id])
          authorize employee, :show?
          latest_invitation = employee.employee_invitations.order(created_at: :desc).first

          render json: {
            employee: employee_json(employee, include_nudge: true).merge(
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
            preferred_channel: params[:preferred_channel].presence || "whatsapp",
            confirm_additional: confirm_additional?,
            planned_participant: planned_participant
          )

          render json: {
            employee: employee_json(result[:employee]),
            invitation_id: result[:invitation].id,
            discover_url: result[:discover_url],
            additional: result[:additional]
          }, status: :created
        end

        # Every row is checked — the invitations are open, the extras confirmed,
        # each person valid — before anyone is invited, so a bad row leaves
        # nobody half-invited.
        def bulk_create
          authorize Employee, :create?
          rows = Array(params[:employees]).map { |row| bulk_row(row) }
          return render json: { error: "Add at least one person" }, status: :unprocessable_entity if rows.empty?

          Engagements::StaffInvitations.new(current_company).check!(adding: rows.size, confirmed: confirm_additional?)
          errors = bulk_errors(rows)
          return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

          created = []
          batch_id = SecureRandom.uuid
          rows.each do |row|
            result = InviteEmployeeService.call(company: current_company, invited_by: current_company_user,
                                                confirm_additional: confirm_additional?, **row)
            result[:invitation].update!(batch_id: batch_id)
            created << employee_json(result[:employee]).merge(
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
            employee: employee_json(result[:employee])
          }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
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

        def confirm_additional? = ActiveModel::Type::Boolean.new.cast(params[:confirm_additional]) == true

        # Inviting someone the key user planned for during onboarding (P3) ties the
        # plan to the employee, so the plan shows them as invited.
        def planned_participant
          return if params[:engagement_participant_id].blank?

          current_company.current_engagement&.participants&.employees
                         &.find_by(id: params[:engagement_participant_id], employee_id: nil)
        end

        def bulk_row(row)
          row = row.respond_to?(:permit) ? row.permit(:phone_e164, :display_name, :department, :email) : row.to_h
          row.to_h.symbolize_keys.slice(:phone_e164, :display_name, :department, :email)
        end

        def bulk_errors(rows)
          phones = []
          rows.each_with_index.filter_map do |row, i|
            phone = begin
              PhoneNormalizer.call(row[:phone_e164])
            rescue StandardError
              nil
            end
            employee = current_company.employees.new(phone_e164: phone, display_name: row[:display_name],
                                                     email: row[:email].to_s.strip.downcase.presence,
                                                     participation_status: "invited", onboarding_step: "awaiting_name")
            messages = employee.valid? ? [] : employee.errors.full_messages
            messages << "Phone appears twice in this list" if phone && phones.include?(phone)
            phones << phone
            "Row #{i + 1}: #{messages.to_sentence}" if messages.any?
          end
        end

        def employee_json(employee, include_nudge: false)
          json = {
            id: employee.id,
            phone_e164: employee.phone_e164,
            email: employee.email,
            preferred_channel: employee.preferred_channel,
            display_name: employee.display_name,
            department: employee.department,
            role_title: employee.role_title,
            seniority: employee.seniority,
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
