# frozen_string_literal: true

module Api
  module V1
    module Platform
      class CompaniesController < BaseController
        def index
          companies = policy_scope(::Company).includes(:subscription).order(created_at: :desc)
          render json: { companies: companies.map { |c| company_json(c) } }
        end

        def show
          company = policy_scope(::Company).includes(:subscription, :company_users).find(params[:id])
          authorize company, :show?
          render json: { company: company_detail_json(company) }
        end

        def update
          company = ::Company.find(params[:id])
          attrs = company_update_params
          # Settings are merged, not replaced: saving one setting must not wipe
          # every other one the company has.
          attrs[:settings] = (company.settings || {}).merge(attrs[:settings].to_h) if attrs.key?(:settings)
          company.update!(attrs)
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "company_updated",
            target: company,
            request: request
          )
          render json: { company: company_detail_json(company) }
        end

        private

        def company_update_params
          params.require(:company).permit(:name, :display_name, :locale, settings: {})
        end

        def company_json(company)
          {
            id: company.id,
            name: company.name,
            slug: company.slug,
            display_name: company.display_name,
            locale: company.locale,
            report_readiness_score: company.report_readiness_score,
            portal_onboarding_completed_at: company.portal_onboarding_completed_at,
            approval_status: company.approval_status,
            engagement_status: company.current_engagement&.status,
            subscription: subscription_json(company.subscription),
            created_at: company.created_at
          }
        end

        def company_detail_json(company)
          engagement = company.current_engagement
          company_json(company).merge(
            engagement: engagement && EngagementsController.engagement_json(engagement),
            settings: company.merged_settings,
            company_users: company.company_users.map do |u|
              { id: u.id, email: u.email, name: u.name, role: u.role, status: u.status }
            end,
            company_profile: company.company_profile || {},
            profile_provenance: company.profile_provenance || {},
            onboarding_answers: company.questionnaire_answers || {},
            website_url: company.website_url
          )
        end

        def subscription_json(sub)
          return nil unless sub

          {
            plan: sub.plan,
            status: sub.status,
            trial_ends_at: sub.trial_ends_at,
            conversations_used: sub.conversations_used
          }
        end
      end
    end
  end
end
