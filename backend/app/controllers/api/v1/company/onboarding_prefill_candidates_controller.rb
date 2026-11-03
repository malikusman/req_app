# frozen_string_literal: true

module Api
  module V1
    module Company
      # The key user's answer to each website proposal (Doc 07 §5.4):
      # - confirm: the proposal becomes a fact, recorded as PREFILL_CONFIRMED;
      # - correct: the key user edits it on the form, and what they save is theirs
      #   (USER_ENTERED); the website's value stays on the candidate as evidence;
      # - reject: nothing is written.
      # A proposal left alone stays INFERRED, and nothing downstream reads it.
      class OnboardingPrefillCandidatesController < BaseController
        def confirm
          authorize :onboarding, :update_profile?
          candidate = decide!("CONFIRMED") or return
          mapped = Companies::PrefillAnswers.for(candidate)
          current_company.update!(questionnaire_answers: (current_company.questionnaire_answers || {}).merge(mapped))
          Companies::OnboardingSync.call(company: current_company, answers: mapped, actor: current_company_user,
                                         provenance: "PREFILL_CONFIRMED")
          render json: { candidate: self.class.candidate_json(candidate, current_company), answers: mapped }
        end

        # The proposal's answers come back so the form can fill them in for editing;
        # they are written when the key user saves the form.
        def correct
          authorize :onboarding, :update_profile?
          candidate = decide!("CORRECTED") or return
          render json: { candidate: self.class.candidate_json(candidate, current_company),
                         answers: Companies::PrefillAnswers.for(candidate) }
        end

        def reject
          authorize :onboarding, :update_profile?
          candidate = decide!("REJECTED") or return
          render json: { candidate: self.class.candidate_json(candidate, current_company) }
        end

        # What the onboarding screen shows for each proposal. `conflicts` marks one
        # that disagrees with a value the key user already gave: shown as "your
        # website says…", never applied by itself (Doc 07 §5.5).
        def self.candidate_json(candidate, company)
          key = Companies::PrefillAnswers::PROFILE_KEYS[candidate.target_field]
          source = key && company.profile_provenance.dig(key, "source")
          current = key && company.company_profile[key]
          {
            id: candidate.id,
            target_field: candidate.target_field,
            display_text: candidate.display_text.presence || Array(candidate.value).join(", "),
            evidence_excerpt: candidate.evidence_excerpt,
            source_url: candidate.source_url,
            confidence: candidate.confidence,
            status: candidate.status,
            conflicts: candidate.status == "PROPOSED" && current.present? && source != "PREFILL_CONFIRMED"
          }
        end

        private

        def decide!(status)
          candidate = current_company.current_engagement&.prefill_candidates&.find_by(id: params[:id])
          unless candidate
            head :not_found
            return nil
          end
          unless candidate.status == "PROPOSED" || candidate.status == status
            render json: { errors: ["This proposal has already been answered"] }, status: :unprocessable_entity
            return nil
          end

          candidate.update!(status: status, decided_by: current_company_user, decided_at: Time.current)
          candidate
        end
      end
    end
  end
end
