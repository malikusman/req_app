# frozen_string_literal: true

module Api
  module V1
    module Company
      class EmployeeValuePreferencesController < BaseController
        def show
          employee = current_company.employees.find(params[:employee_id])
          preference = EmployeeValuePreference.find_or_initialize_by(employee: employee)
          render json: { employee_value_preference: preference_json(preference) }
        end

        def update
          employee = current_company.employees.find(params[:employee_id])
          preference = EmployeeValuePreference.find_or_initialize_by(employee: employee)
          preference.assign_attributes(preference_params)
          if ActiveModel::Type::Boolean.new.cast(params.dig(:employee_value_preference, :email_opt_in)) == false
            preference.unsubscribed_at ||= Time.current
          elsif ActiveModel::Type::Boolean.new.cast(params.dig(:employee_value_preference, :email_opt_in))
            preference.unsubscribed_at = nil
          end
          preference.save!
          render json: { employee_value_preference: preference_json(preference) }
        end

        private

        def preference_params
          params.require(:employee_value_preference).permit(:email_opt_in, :frequency, :locale, interests: [])
        end

        def preference_json(preference)
          {
            employee_id: preference.employee_id,
            email_opt_in: preference.email_opt_in,
            frequency: preference.frequency,
            locale: preference.locale,
            interests: preference.interests,
            unsubscribed_at: preference.unsubscribed_at,
            subscribed: preference.persisted? ? preference.subscribed? : false
          }
        end
      end
    end
  end
end
