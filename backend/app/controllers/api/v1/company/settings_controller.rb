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
          settings = current_company.settings.merge(organization_params)
          current_company.update!(
            display_name: params[:display_name] || current_company.display_name,
            locale: params[:locale] || current_company.locale,
            settings: settings
          )
          render json: { ok: true, settings: current_company.merged_settings }
        end

        def security
          authorize :settings, :security?
          active_codes = EmployeeAccessCode.where(company: current_company, status: "active").count
          render json: {
            security_snapshot: current_company.security_snapshot,
            pin_rotated_at: current_company.pin_rotated_at,
            active_access_codes: active_codes
          }
        end

        def rotate_access_codes
          authorize :settings, :rotate_access_codes?
          count = AccessCodes::RotateAllService.call(company: current_company, rotated_by: current_company_user)
          current_company.update!(pin_rotated_at: Time.current)
          render json: { ok: true, codes_rotated: count }
        end

        private

        def organization_params
          params.permit(department_targets: {}, custom_departments: [], report_thresholds: {}).to_h
        end
      end
    end
  end
end
