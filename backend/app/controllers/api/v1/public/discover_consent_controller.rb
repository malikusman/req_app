# frozen_string_literal: true

module Api
  module V1
    module Public
      # Web consent for the avatar interview. The WhatsApp flow asks the employee to
      # "reply YES"; on the web the employee reads a plain statement and presses a
      # button. Acceptance has the same effects as a YES (OnboardingHandler#accept_consent!):
      # consent time and version recorded, then profiling or discovery starts.
      class DiscoverConsentController < ApplicationController
        include EmployeeWebAuthenticatable

        # GET /api/v1/public/discover/consent
        def show
          render json: { required: current_employee.onboarding_step == "awaiting_consent",
                         text: Voice::InterviewerPhrases.consent_text, version: Voice::InterviewerPhrases.consent_version }
        end

        # POST /api/v1/public/discover/consent { version }
        def create
          unless current_employee.onboarding_step == "awaiting_consent"
            return render json: { accepted: true, already: true } # idempotent: a retried click
          end
          # The version proves which wording the employee saw; a stale page must reload.
          unless params[:version].to_s == Voice::InterviewerPhrases.consent_version
            return render json: { error: "The consent wording changed. Please review it again." }, status: :conflict
          end

          accepted = current_conversation.with_lock do
            Whatsapp::OnboardingHandler.new(employee: current_employee, conversation: current_conversation,
                                            client: Web::CapturingMetaClient.new, channel: "web")
                                       .accept_consent!(version: Voice::InterviewerPhrases.consent_version)
          end
          return render json: { error: "Discovery is temporarily unavailable for your organization." }, status: :unprocessable_entity unless accepted

          current_conversation.increment!(:discovery_state_version)
          render json: { accepted: true }
        end
      end
    end
  end
end
