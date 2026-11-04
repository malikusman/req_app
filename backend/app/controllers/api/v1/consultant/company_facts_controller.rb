# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # A consultant correcting the client's facts (O1–O11) once onboarding has
      # been submitted (Doc 07 §12). The answers go through the same validation and
      # sync as the key user's, recorded as found later in conversation and by
      # this consultant, and each change is kept in the company's change history.
      # Who takes part and the key user's language are not a consultant's to edit.
      class CompanyFactsController < BaseController
        Fields = Companies::OnboardingFields

        before_action :set_company

        def update
          unless @company.current_engagement&.onboarding_submitted_at
            return render json: { error: "The client hasn't submitted their company profile yet" },
                          status: :unprocessable_entity
          end

          incoming = params[:answers] || {}
          incoming = incoming.respond_to?(:to_unsafe_h) ? incoming.to_unsafe_h : incoming.to_h
          clean, errors = Fields.sanitize(incoming.stringify_keys.slice(*Fields::FACT_KEYS))
          return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

          ActiveRecord::Base.transaction do
            answers = (@company.questionnaire_answers || {}).merge(clean)
            @company.update!(questionnaire_answers: answers)
            Companies::OnboardingSync.call(company: @company, answers: answers, actor: current_consultant_user,
                                           provenance: "DISCOVERED_LATER")
          end

          @company.reload
          render json: {
            company_profile: @company.company_profile || {},
            profile_provenance: @company.profile_provenance || {},
            onboarding_answers: @company.questionnaire_answers || {},
            profile_changes: ProfileChange.recent_json(@company)
          }
        end

        private

        def set_company
          @company = ::Company.find(params[:company_id])
          raise ActiveRecord::RecordNotFound unless assigned_company_ids.include?(@company.id)
        end
      end
    end
  end
end
