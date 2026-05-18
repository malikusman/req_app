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

        def create
          authorize ::Company, :create?
          company = nil
          ActiveRecord::Base.transaction do
            company = ::Company.create!(company_params)
            Subscription.create!(
              company: company,
              plan: "trial",
              status: "trial",
              trial_ends_at: 14.days.from_now
            )
            if params[:company_admin].present?
              admin_params = params.require(:company_admin).permit(:email, :name, :password)
              CompanyUser.create!(
                company: company,
                email: admin_params[:email].downcase,
                name: admin_params[:name],
                password: admin_params[:password],
                role: "company_admin",
                status: "active"
              )
            end
          end

          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "company_created",
            target: company,
            metadata: { name: company.name },
            request: request
          )

          render json: { company: company_detail_json(company.reload) }, status: :created
        end

        def update
          company = ::Company.find(params[:id])
          company.update!(company_update_params)
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "company_updated",
            target: company,
            request: request
          )
          render json: { company: company_detail_json(company) }
        end

        private

        def company_params
          params.require(:company).permit(:name, :display_name, :locale)
        end

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
            subscription: subscription_json(company.subscription),
            created_at: company.created_at
          }
        end

        def company_detail_json(company)
          company_json(company).merge(
            settings: company.merged_settings,
            company_users: company.company_users.map do |u|
              { id: u.id, email: u.email, name: u.name, role: u.role, status: u.status }
            end
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
