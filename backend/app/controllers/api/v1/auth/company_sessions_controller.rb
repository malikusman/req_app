# frozen_string_literal: true

module Api
  module V1
    module Auth
      class CompanySessionsController < ApplicationController
        def create
          user = CompanyUser.find_by(email: params[:email]&.downcase, status: "active")
          unless user&.authenticate(params[:password])
            return render json: { error: "Invalid email or password" }, status: :unauthorized
          end

          unless user.company.approved_for_access?
            return render json: { error: "Company account is pending approval" }, status: :forbidden
          end

          unless user.company.subscription&.active_for_access?
            return render json: { error: "Subscription inactive" }, status: :forbidden
          end

          token = JsonWebToken.encode(
            {
              sub: "company_user:#{user.id}",
              aud: "company",
              company_id: user.company_id,
              role: user.role,
              jti: user.jti
            }
          )

          render json: {
            token: token,
            user: company_user_json(user),
            company: company_json(user.company)
          }
        end

        private

        def company_user_json(user)
          {
            id: user.id,
            email: user.email,
            name: user.name,
            role: user.role,
            onboarding_completed_at: user.onboarding_completed_at
          }
        end

        def company_json(company)
          {
            id: company.id,
            name: company.name,
            display_name: company.display_name,
            locale: company.locale,
            portal_onboarding_completed_at: company.portal_onboarding_completed_at
          }
        end
      end
    end
  end
end
