# frozen_string_literal: true

module Api
  module V1
    module Company
      class MeController < BaseController
        def show
          enforcer = Subscriptions::ConversationLimitEnforcer.new(company: current_company)
          render json: {
            user: user_json(current_company_user),
            company: company_json(current_company),
            impersonating: impersonating?,
            impersonation_expires_at: impersonation_session&.expires_at,
            usage: enforcer.usage_summary
          }
        end

        def update
          attrs = {}
          attrs[:name] = params[:name].to_s.strip if params.key?(:name)
          if params.key?(:phone)
            phone = normalize_phone(params[:phone])
            if params[:phone].to_s.strip.present? && phone.blank?
              return render json: { error: "Phone number is invalid" }, status: :unprocessable_entity
            end
            attrs[:phone] = phone
          end
          current_company_user.update!(attrs) if attrs.any?

          render json: { ok: true, user: user_json(current_company_user.reload) }
        end

        private

        def user_json(user)
          {
            id: user.id,
            email: user.email,
            name: user.name,
            phone: user.phone,
            role: user.role,
            onboarding_completed_at: user.onboarding_completed_at
          }
        end

        def normalize_phone(value)
          raw = value.to_s.strip
          return nil if raw.blank?

          digits = raw.gsub(/[^\d+]/, "")
          digits.presence
        end

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
