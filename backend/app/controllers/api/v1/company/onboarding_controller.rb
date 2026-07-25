# frozen_string_literal: true

module Api
  module V1
    module Company
      class OnboardingController < BaseController
        def show
          authorize :onboarding, :show?
          progress = Companies::QuestionnaireProgress.call(current_company.questionnaire_answers)
          render json: {
            step: current_company.questionnaire_step.to_i.clamp(1, 10),
            portal_onboarding_completed_at: current_company.portal_onboarding_completed_at,
            questionnaire_completed_at: current_company.questionnaire_completed_at,
            questionnaire_answers: current_company.questionnaire_answers || {},
            completion_percent: progress[:completion_percent],
            section_status: progress[:section_status],
            company: {
              display_name: current_company.display_name,
              locale: current_company.locale,
              logo_storage_key: current_company.logo_storage_key,
              engagement_mode: current_company.engagement_mode,
              company_profile: current_company.company_profile,
              known_systems: current_company.company_systems.active.order(:name).pluck(:name)
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
          current_company.update!(attrs)

          Companies::ProfileUpdater.call(
            company: current_company,
            profile_params: profile_params,
            known_systems: known_systems_param
          )

          render json: {
            ok: true,
            company_profile: current_company.reload.company_profile
          }
        end

        def update_questionnaire
          authorize :onboarding, :update_profile?
          answers = (current_company.questionnaire_answers || {}).merge(questionnaire_answers_param)
          step = params[:questionnaire_step].presence&.to_i
          step = step.clamp(1, 10) if step

          attrs = { questionnaire_answers: answers }
          attrs[:questionnaire_step] = step if step
          current_company.update!(attrs)

          Companies::QuestionnaireSync.call(company: current_company, answers: answers)

          progress = Companies::QuestionnaireProgress.call(answers)
          if progress[:completion_percent] >= 100 && current_company.questionnaire_completed_at.blank?
            current_company.update!(questionnaire_completed_at: Time.current)
          end

          render json: {
            ok: true,
            questionnaire_answers: current_company.reload.questionnaire_answers,
            questionnaire_step: current_company.questionnaire_step,
            questionnaire_completed_at: current_company.questionnaire_completed_at,
            completion_percent: progress[:completion_percent],
            section_status: progress[:section_status]
          }
        end

        def complete
          authorize :onboarding, :complete?
          settings = (current_company.settings.presence || {}).merge("engagement_mode" => "hybrid")

          progress = Companies::QuestionnaireProgress.call(current_company.questionnaire_answers)
          attrs = {
            portal_onboarding_completed_at: Time.current,
            settings: settings
          }
          if params[:mark_questionnaire_complete].present? || progress[:completion_percent] >= 100
            attrs[:questionnaire_completed_at] = Time.current
          end

          current_company.update!(attrs)
          current_company_user.update!(onboarding_completed_at: Time.current)
          render json: {
            ok: true,
            redirect_to: "/company/dashboard",
            completion_percent: progress[:completion_percent]
          }
        end

        private

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

        def known_systems_param
          return nil unless params.key?(:known_systems)

          Array(params[:known_systems])
        end

        def questionnaire_answers_param
          raw = params[:questionnaire_answers] || params[:answers] || {}
          return {} unless raw.respond_to?(:to_unsafe_h) || raw.is_a?(Hash)

          hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
          hash.stringify_keys.slice(*Companies::QuestionnaireProgress::FIELD_IDS)
        end
      end
    end
  end
end
