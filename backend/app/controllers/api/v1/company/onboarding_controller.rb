# frozen_string_literal: true

module Api
  module V1
    module Company
      class OnboardingController < BaseController
        def show
          authorize :onboarding, :show?
          render json: {
            step: current_step,
            company: {
              display_name: current_company.display_name,
              locale: current_company.locale,
              logo_storage_key: current_company.logo_storage_key,
              engagement_mode: current_company.engagement_mode
            },
            invited_count: current_company.employees.count
          }
        end

        def update_profile
          authorize :onboarding, :update_profile?
          attrs = {
            display_name: params[:display_name].presence || current_company.name,
            locale: params[:locale].presence || "en"
          }
          if params[:engagement_mode].present?
            mode = params[:engagement_mode].to_s
            mode = "hybrid" unless ::Company::ENGAGEMENT_MODES.include?(mode)
            attrs[:settings] = current_company.settings.merge("engagement_mode" => mode)
          end
          current_company.update!(attrs)
          render json: { ok: true, step: 2, engagement_mode: current_company.engagement_mode }
        end

        def complete
          authorize :onboarding, :complete?
          settings = current_company.settings.presence || {}
          settings = settings.merge("engagement_mode" => "hybrid") if settings["engagement_mode"].blank?
          # Docs-first: if finishing with zero employees, stay hybrid/docs — never force interview mode.
          if current_company.employees.none? && settings["engagement_mode"] == "interview"
            settings = settings.merge("engagement_mode" => "hybrid")
          end
          current_company.update!(
            portal_onboarding_completed_at: Time.current,
            settings: settings
          )
          current_company_user.update!(onboarding_completed_at: Time.current)
          render json: { ok: true, redirect_to: "/company/dashboard" }
        end

        private

        def current_step
          return 3 if current_company.portal_onboarding_completed_at.present?
          return 2 if current_company.display_name.present?

          1
        end
      end
    end
  end
end
