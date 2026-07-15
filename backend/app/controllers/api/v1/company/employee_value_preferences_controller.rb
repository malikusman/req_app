# frozen_string_literal: true

module Api
  module V1
    module Company
      class EmployeeValuePreferencesController < BaseController
        before_action :require_company_admin!, only: %i[update generate_digest send_digest]

        def show
          employee = find_employee!
          preference = EmployeeValuePreference.find_or_initialize_by(employee: employee)
          render json: {
            employee_value_preference: preference_json(preference),
            latest_digest: latest_digest_json(employee)
          }
        end

        def update
          employee = find_employee!
          preference = EmployeeValuePreference.find_or_initialize_by(employee: employee)
          preference.assign_attributes(preference_params)
          if ActiveModel::Type::Boolean.new.cast(params.dig(:employee_value_preference, :email_opt_in)) == false
            preference.unsubscribed_at ||= Time.current
          elsif ActiveModel::Type::Boolean.new.cast(params.dig(:employee_value_preference, :email_opt_in))
            preference.unsubscribed_at = nil
          end
          preference.save!
          render json: {
            employee_value_preference: preference_json(preference),
            latest_digest: latest_digest_json(employee)
          }
        end

        def generate_digest
          employee = find_employee!
          digest = EmployeeValue::GenerateDigestService.call(
            employee: employee,
            period_key: params[:period_key]
          )
          render json: { digest: digest_json(digest) }
        end

        def send_digest
          employee = find_employee!
          preference = EmployeeValuePreference.find_or_initialize_by(employee: employee)
          unless preference.subscribed?
            return render json: { error: "Employee must be opted in before sending a digest" }, status: :unprocessable_entity
          end
          if employee.email.blank?
            return render json: { error: "Employee has no email address" }, status: :unprocessable_entity
          end

          digest = EmployeeValue::GenerateDigestService.call(
            employee: employee,
            period_key: params[:period_key]
          )
          digest.update!(status: "reviewed") if digest.status == "draft"
          EmployeeValue::SendDigestService.call(digest: digest)

          render json: {
            digest: digest_json(digest.reload),
            message: "Digest queued for #{employee.email}"
          }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def find_employee!
          current_company.employees.find(params[:employee_id])
        end

        def require_company_admin!
          return if current_company_user.company_admin?

          render json: { error: "Forbidden" }, status: :forbidden
        end

        def preference_params
          params.require(:employee_value_preference).permit(:email_opt_in, :frequency, :locale, interests: [])
        end

        def preference_json(preference)
          {
            employee_id: preference.employee_id,
            email_opt_in: preference.email_opt_in,
            frequency: preference.frequency || "monthly",
            locale: preference.locale || "en",
            interests: preference.interests || [],
            unsubscribed_at: preference.unsubscribed_at,
            subscribed: preference.persisted? ? preference.subscribed? : false
          }
        end

        def latest_digest_json(employee)
          digest = employee.employee_value_digests.order(generated_at: :desc, id: :desc).first
          digest && digest_json(digest)
        end

        def digest_json(digest)
          {
            id: digest.id,
            employee_id: digest.employee_id,
            period_key: digest.period_key,
            status: digest.status,
            delivery_status: digest.delivery_status,
            generated_at: digest.generated_at,
            sent_at: digest.sent_at,
            headline: digest.content.is_a?(Hash) ? digest.content["headline"] : nil,
            content: digest.content
          }
        end
      end
    end
  end
end
