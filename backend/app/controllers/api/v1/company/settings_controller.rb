# frozen_string_literal: true

module Api
  module V1
    module Company
      class SettingsController < BaseController
        def organization
          authorize :settings, :organization?
          render json: {
            settings: current_company.merged_settings,
            company: {
              display_name: current_company.display_name,
              locale: current_company.locale,
              company_profile: current_company.company_profile,
              known_systems: current_company.company_systems.active.order(:name).pluck(:name)
            }
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

          if params.key?(:company_profile) || params.key?(:known_systems)
            Companies::ProfileUpdater.call(
              company: current_company,
              profile_params: profile_params,
              known_systems: params.key?(:known_systems) ? Array(params[:known_systems]) : nil
            )
          end

          render json: {
            ok: true,
            settings: current_company.merged_settings,
            company_profile: current_company.reload.company_profile
          }
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
          permitted = params.permit(
            :engagement_mode,
            department_targets: {},
            custom_departments: [],
            report_thresholds: {}
          ).to_h
          if permitted["engagement_mode"].present?
            mode = permitted["engagement_mode"].to_s
            permitted.delete("engagement_mode") unless Company::ENGAGEMENT_MODES.include?(mode)
          end
          permitted
        end

        def profile_params
          params.fetch(:company_profile, {}).permit(
            :industry, :sub_industry, :size_band, :region, :country,
            :annual_revenue_band, :business_goals, org_departments: []
          ).to_h
        end
      end
    end
  end
end
