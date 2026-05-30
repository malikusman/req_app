# frozen_string_literal: true

module Api
  module V1
    module Company
      class SettingsController < BaseController
        def organization
          authorize :settings, :organization?
          render json: {
            settings: current_company.merged_settings,
            company: { display_name: current_company.display_name, locale: current_company.locale }
          }
        end

        def update_organization
          authorize :settings, :update_organization?
          locale = params[:locale].presence || current_company.locale
          unless ::Company::LOCALES.include?(locale)
            return render json: { error: "Invalid locale" }, status: :unprocessable_entity
          end

          settings = current_company.settings.merge(organization_params)
          current_company.update!(
            display_name: params[:display_name] || current_company.display_name,
            locale: locale,
            settings: settings
          )
          render json: { ok: true, settings: current_company.merged_settings }
        end

        def security
          authorize :settings, :security?
          current_company.ensure_join_code!
          render json: {
            security_snapshot: current_company.security_snapshot,
            pin_rotated_at: current_company.pin_rotated_at,
            company_join_code: current_company.join_code
          }
        end

        def rotate_access_codes
          authorize :settings, :rotate_access_codes?
          new_code = AccessCodes::RotateAllService.call(company: current_company, rotated_by: current_company_user)
          render json: { ok: true, company_join_code: new_code }
        end

        private

        def organization_params
          params.permit(department_targets: {}, custom_departments: [], report_thresholds: {}).to_h
        end
      end
    end
  end
end
