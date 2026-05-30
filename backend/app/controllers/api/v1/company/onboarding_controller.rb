# frozen_string_literal: true

module Api
  module V1
    module Company
      class OnboardingController < BaseController
        skip_before_action :require_active_subscription!

        def show
          authorize :onboarding, :show?
          completeness = Companies::ProfileCompleteness.call(company: current_company)
          render json: {
            step: current_step,
            total_steps: Companies::ProfileContextSchema::TOTAL_ONBOARDING_STEPS,
            profile_context: current_company.profile_context,
            completeness: completeness,
            company: {
              name: current_company.name,
              display_name: current_company.display_name,
              logo_storage_key: current_company.logo_storage_key
            },
            invited_count: current_company.employees.count,
            documents_count: current_company.documents.where(source: "company_portal_upload").count
          }
        end

        def update_profile
          authorize :onboarding, :update_profile?
          section = params.require(:section).to_s
          unless Companies::ProfileContextSchema.permitted_section?(section)
            return render json: { error: "Invalid section" }, status: :unprocessable_entity
          end

          current_company.merge_profile_section!(section: section, data: profile_data_param)
          completeness = Companies::ProfileCompleteness.call(company: current_company.reload)

          render json: {
            ok: true,
            step: current_step,
            completeness: completeness,
            profile_context: current_company.profile_context
          }
        end

        def complete
          authorize :onboarding, :complete?
          completeness = Companies::ProfileCompleteness.new(company: current_company)
          unless completeness.required_sections_complete?
            return render json: {
              error: "Complete all required profile sections before finishing setup",
              missing_required_sections: completeness.missing_required_sections
            }, status: :unprocessable_entity
          end

          current_company.update!(portal_onboarding_completed_at: Time.current)
          current_company_user.update!(onboarding_completed_at: Time.current)
          render json: { ok: true, redirect_to: "/company/dashboard" }
        end

        private

        def profile_data_param
          params.require(:data).permit!.to_h
        end

        def current_step
          Companies::ProfileCompleteness.new(company: current_company).current_onboarding_step
        end
      end
    end
  end
end
