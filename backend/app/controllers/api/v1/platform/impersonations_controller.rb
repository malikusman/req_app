# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ImpersonationsController < BaseController
        def create
          company = ::Company.find(params[:company_id])
          result = ::Platform::ImpersonationService.start!(
            platform_user: current_platform_user,
            company: company,
            request: request
          )

          render json: {
            token: result[:token],
            expires_at: result[:expires_at],
            company: {
              id: company.id,
              name: company.name,
              display_name: company.display_name,
              portal_onboarding_completed_at: company.portal_onboarding_completed_at
            },
            user: {
              id: result[:company_user].id,
              email: result[:company_user].email,
              name: result[:company_user].name,
              role: result[:company_user].role
            }
          }
        end
      end
    end
  end
end
