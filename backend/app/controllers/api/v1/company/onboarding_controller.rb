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
              logo_storage_key: current_company.logo_storage_key
            },
            invited_count: current_company.employees.count
          }
        end

        def update_profile
          authorize :onboarding, :update_profile?
          current_company.update!(
            display_name: params[:display_name].presence || current_company.name,
            locale: params[:locale].presence || "en"
          )
          render json: { ok: true, step: 2 }
        end

        def complete
          authorize :onboarding, :complete?
          current_company.update!(portal_onboarding_completed_at: Time.current)
          current_company_user.update!(onboarding_completed_at: Time.current)
          render json: { ok: true, redirect_to: "/company/dashboard" }
        end

        private

        def current_step
          return 3 if current_company.portal_onboarding_completed_at.present?
          return 2 if current_company.display_name.present? && current_company.employees.any?
          return 1 if current_company.display_name.present?

          1
        end
      end
    end
  end
end
