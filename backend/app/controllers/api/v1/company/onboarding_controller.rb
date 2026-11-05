# frozen_string_literal: true

module Api
  module V1
    module Company
      # The key user's onboarding (Doc 07): one short screen of facts, participant
      # planning and the confidentiality acknowledgement. Answers autosave; saving
      # a group folds them into the company profile; submitting hands the
      # engagement over to the key-person conversation. After submitting, the same
      # screen edits the facts.
      class OnboardingController < BaseController
        Fields = Companies::OnboardingFields

        def show
          authorize :onboarding, :show?
          render json: state_json
        end

        def update_profile
          authorize :onboarding, :update_profile?
          # A field left out of the request keeps its value: saving only the
          # website used to reset the language to English and the display name.
          attrs = {
            display_name: params[:display_name].presence || current_company.display_name.presence || current_company.name,
            locale: params[:locale].presence || current_company.locale.presence || "en"
          }
          current_company.update!(attrs)

          Companies::ProfileUpdater.call(
            company: current_company,
            profile_params: profile_params,
            known_systems: known_systems_param,
            website_url: params.key?(:website_url) ? params[:website_url] : :omit,
            actor: current_company_user
          )
          current_company.update!(docs_profile_stale_at: Time.current) if current_company.documents.ready.exists?

          render json: {
            ok: true,
            company_profile: current_company.reload.company_profile,
            website_url: current_company.website_url
          }
        end

        # Moving between groups: store the answers and fold them into the profile.
        def update_questionnaire
          authorize :onboarding, :update_profile?
          answers = merged_answers or return

          attrs = { questionnaire_answers: answers }
          attrs[:questionnaire_step] = params[:questionnaire_step].to_i if params[:questionnaire_step].present?
          current_company.update!(attrs)
          sync!(answers)
          render json: state_json
        end

        # Autosave. Stores answers and nothing else; the profile is updated when a
        # group is left or the form is submitted, not on every keystroke.
        def update_questionnaire_answers
          authorize :onboarding, :update_profile?
          answers = merged_answers or return

          current_company.update!(questionnaire_answers: answers)
          render json: { ok: true }
        end

        def submit
          authorize :onboarding, :submit?
          engagement = current_company.current_engagement
          return render json: { errors: ["There is no engagement to onboard"] }, status: :unprocessable_entity unless engagement

          answers = merged_answers or return
          acknowledged = ActiveModel::Type::Boolean.new.cast(params[:confidentiality_acknowledged]) ||
                         engagement.confidentiality_acknowledged_at.present?
          errors = submit_errors(engagement, answers, acknowledged)
          return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

          ActiveRecord::Base.transaction do
            current_company.update!(questionnaire_answers: answers)
            sync!(answers)
            acknowledge!(engagement) if engagement.confidentiality_acknowledged_at.blank?
            first_submission = engagement.onboarding_submitted_at.blank?
            engagement.update!(onboarding_submitted_at: Time.current) if first_submission
            current_company.update!(portal_onboarding_completed_at: Time.current) if current_company.portal_onboarding_completed_at.blank?
            current_company_user.update!(onboarding_completed_at: Time.current) if current_company_user.onboarding_completed_at.blank?
            hand_over!(engagement.reload)
          end
          # After the commit, so the job sees the hand-over. Safe on a resubmit.
          KeyPersonKickoffJob.perform_later(engagement.id) if engagement.reload.status == "KEY_PERSON_DISCOVERY"
          render json: state_json.merge(redirect_to: "/company/dashboard")
        rescue Engagements::Transition::Error => e
          render json: { errors: [e.message] }, status: :unprocessable_entity
        end

        private

        def state_json
          engagement = current_company.current_engagement
          answers = current_company.questionnaire_answers || {}
          {
            answers: answers,
            step: current_company.questionnaire_step,
            submitted_at: engagement&.onboarding_submitted_at,
            missing_for_submit: engagement ? submit_errors(engagement, answers, engagement.confidentiality_acknowledged_at.present?) : [],
            company: {
              display_name: current_company.display_name,
              locale: current_company.locale,
              website_url: current_company.website_url,
              company_profile: current_company.company_profile,
              profile_provenance: current_company.profile_provenance
            },
            key_user: {
              name: current_company_user.name,
              phone: current_company_user.phone,
              job_title: current_company_user.job_title,
              preferred_language: current_company_user.preferred_language
            },
            engagement: engagement && {
              status: engagement.status,
              scope_type: engagement.scope_type,
              departments_in_scope: engagement.departments_in_scope,
              languages: engagement.languages,
              planned_departments: engagement.planned_departments,
              planned_participant_count: engagement.planned_participant_count,
              confidentiality_acknowledged_at: engagement.confidentiality_acknowledged_at
            },
            # Proposals read from the website (Doc 07 §5), for the key user to confirm.
            prefill: engagement && {
              status: engagement.prefill_status,
              entity_note: engagement.prefill_entity_note,
              candidates: engagement.prefill_candidates.order(:id).map { |c|
                OnboardingPrefillCandidatesController.candidate_json(c, current_company)
              }
            },
            confidentiality: {
              version: Fields::CONFIDENTIALITY_VERSION,
              text: format(Fields::CONFIDENTIALITY_TEXT, company: current_company.display_name.presence || current_company.name)
            }
          }
        end

        # What still stands between the key user and submitting. P2 counts may be
        # "Not sure" — they are settled before pricing, not here (Doc 07 §10).
        def submit_errors(engagement, answers, acknowledged)
          errors = []
          departments = Array(answers["p1_departments"]) - [Fields::NOT_SURE]
          errors << "Choose at least one department to take part" if departments.empty?
          if engagement.scope_type == "DEPARTMENT"
            in_scope = engagement.departments_in_scope.map(&:downcase)
            outside = departments.reject { |d| in_scope.include?(d.downcase) }
            errors << "Only departments in this engagement can take part: #{outside.join(', ')} is not" if outside.any?
          end
          errors << "Please confirm the confidentiality acknowledgement" unless acknowledged
          errors
        end

        def merged_answers
          incoming = params[:answers] || params[:questionnaire_answers] || {}
          incoming = incoming.respond_to?(:to_unsafe_h) ? incoming.to_unsafe_h : incoming.to_h
          clean, errors = Fields.sanitize(incoming)
          if errors.any?
            render json: { errors: errors }, status: :unprocessable_entity
            return nil
          end
          (current_company.questionnaire_answers || {}).merge(clean)
        end

        def sync!(answers)
          Companies::OnboardingSync.call(company: current_company, answers: answers, actor: current_company_user)
          language = Fields::LANGUAGES[answers["a4_language"].to_s]
          current_company_user.update!(preferred_language: language) if language
        end

        def acknowledge!(engagement)
          engagement.update!(confidentiality_acknowledged_at: Time.current,
                             confidentiality_acknowledged_by: current_company_user,
                             confidentiality_text_version: Fields::CONFIDENTIALITY_VERSION)
        end

        # Onboarding done: the engagement moves on to the key-person conversation.
        # An engagement already past onboarding (a company from before engagements)
        # just keeps its facts up to date.
        def hand_over!(engagement)
          if engagement.status == "SET_UP"
            Engagements::Transition.call(engagement: engagement, to: "ONBOARDING", actor: current_company_user)
          end
          return unless engagement.reload.status == "ONBOARDING"

          Engagements::Transition.call(engagement: engagement, to: "KEY_PERSON_DISCOVERY", actor: current_company_user)
        end

        def profile_params
          Companies::ProfileUpdater.permit(params.fetch(:company_profile, {}))
        end

        def known_systems_param
          return nil unless params.key?(:known_systems)

          Array(params[:known_systems])
        end
      end
    end
  end
end
