# frozen_string_literal: true

module Api
  module V1
    module Company
      class MeController < BaseController
        def show
          enforcer = Subscriptions::ConversationLimitEnforcer.new(company: current_company)
          render json: {
            user: {
              id: current_company_user.id,
              email: current_company_user.email,
              name: current_company_user.name,
              role: current_company_user.role,
              onboarding_completed_at: current_company_user.onboarding_completed_at
            },
            company: company_json(current_company),
            impersonating: impersonating?,
            impersonation_expires_at: impersonation_session&.expires_at,
            usage: enforcer.usage_summary
          }
        end

        private

        def company_json(company)
          {
            id: company.id,
            name: company.name,
            display_name: company.display_name,
            locale: company.locale,
            logo_storage_key: company.logo_storage_key,
            settings: company.settings,
            portal_onboarding_completed_at: company.portal_onboarding_completed_at,
            report_readiness_score: company.report_readiness_score,
            report_readiness_breakdown: company.report_readiness_breakdown,
            intelligence_snapshot: company.intelligence_snapshot,
            security_snapshot: company.security_snapshot,
            onboarding_complete: company.onboarding_complete?,
            completed_count: company.completed_count,
            invited_count: company.invited_count
          }
        end
      end
    end
  end
end
