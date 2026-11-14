# frozen_string_literal: true

module Api
  module V1
    module Company
      # The key user's own conversation with leadership (Doc 08), in the portal.
      # Only the engagement's key user has one here; other managers come in by
      # their own link.
      #
      # The key user also has the scope card (Doc 08 §13): the departments and
      # how many people from each, and the people they mentioned. Changing it is
      # open until the engagement moves on to pricing.
      class KeyPersonSessionsController < BaseController
        include KeyPersonConversationEndpoints

        before_action :require_key_user!

        rescue_from KeyPerson::Scope::Locked do
          render json: { error: "The plan is fixed now that Stage 1 is being priced. Your consultant can change it." },
                 status: :conflict
        end

        # PATCH departments: [{ name, count }]
        def update_scope
          stranded = scope_card.update_departments!(params.permit(departments: %i[name count]).fetch(:departments, []))
          warnings = stranded.map do |p|
            "#{p.name} is planned in #{p.department}, which is no longer taking part."
          end
          render json: conversation_json.merge(warnings: warnings)
        rescue ArgumentError => e
          render json: { errors: [e.message] }, status: :unprocessable_entity
        end

        # POST index, participant: { participant_type, name, role_title, department, email, phone_e164 }
        def confirm_person
          scope_card.confirm_person!(
            params.require(:index),
            EngagementParticipant.normalise_contact(
              params.require(:participant).permit(:participant_type, :name, :role_title, :department, :scope, :email,
                                                  :phone_e164, :preferred_language)
            )
          )
          render json: conversation_json, status: :created
        end

        def dismiss_person
          scope_card.dismiss_person!(params.require(:index))
          render json: conversation_json
        end

        private

        def key_participant
          @key_participant ||= current_company.current_engagement.participants.find_by!(source: "KEY_USER")
        end

        def require_key_user!
          engagement = current_company.current_engagement
          return if engagement && engagement.key_user_id == current_company_user.id

          render json: { error: "Only the engagement's key user has this conversation." }, status: :forbidden
        end

        def scope_card
          session = conversation.session or raise(KeyPerson::Turn::NotStarted)
          KeyPerson::Scope.new(session)
        end

        def extra_json(session)
          session ? { scope: KeyPerson::Scope.new(session).json } : {}
        end
      end
    end
  end
end
