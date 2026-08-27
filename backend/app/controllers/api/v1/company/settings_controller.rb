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
              website_url: current_company.website_url,
              company_profile: current_company.company_profile,
              known_systems: current_company.company_systems.active.order(:name).pluck(:name)
            }
          }
        end

        def update_organization
          authorize :settings, :update_organization?
          settings = (current_company.settings || {}).merge(organization_params)
          current_company.update!(
            display_name: params[:display_name] || current_company.display_name,
            locale: params[:locale] || current_company.locale,
            settings: settings
          )

          if params.key?(:company_profile) || params.key?(:known_systems) || params.key?(:website_url)
            Companies::ProfileUpdater.call(
              company: current_company,
              profile_params: profile_params,
              known_systems: params.key?(:known_systems) ? Array(params[:known_systems]) : nil,
              website_url: params.key?(:website_url) ? params[:website_url] : :omit
            )
          end

          render json: {
            ok: true,
            settings: current_company.merged_settings,
            company_profile: current_company.reload.company_profile,
            website_url: current_company.website_url
          }
        end

        def security
          authorize :settings, :security?
          render json: {
            security_snapshot: current_company.security_snapshot
          }
        end

        def refresh_web_research
          authorize :settings, :update_organization?
          if current_company.website_url.blank?
            return render json: { error: "Set a website URL before refreshing research." }, status: :unprocessable_entity
          end

          CompanyWebResearchJob.perform_later(current_company.id, force: true)
          render json: { ok: true, queued: true }
        end

        private

        def organization_params
          permitted = params.permit(
            :engagement_mode,
            :consultant_can_contact_employees,
            department_targets: {},
            custom_departments: [],
            report_thresholds: {}
          ).to_h
          if permitted["engagement_mode"].present?
            mode = permitted["engagement_mode"].to_s
            # Nested under Api::V1::Company — use top-level ::Company model constant.
            permitted.delete("engagement_mode") unless ::Company::ENGAGEMENT_MODES.include?(mode)
          end
          if permitted.key?("consultant_can_contact_employees")
            permitted["consultant_can_contact_employees"] =
              ActiveModel::Type::Boolean.new.cast(permitted["consultant_can_contact_employees"])
          end
          permitted
        end

        def profile_params
          raw = params.fetch(:company_profile, {})
          permitted = raw.permit(
            :industry, :sub_industry, :size_band, :region, :country,
            :annual_revenue_band,
            business_goals: [],
            org_departments: []
          )
          if raw[:business_goals].is_a?(String)
            permitted[:business_goals] = raw[:business_goals]
          end
          permitted.to_h
        end
      end
    end
  end
end
