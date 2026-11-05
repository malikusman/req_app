# frozen_string_literal: true

module Api
  module V1
    module Company
      # The key user's own conversation with leadership (Doc 08), in the portal.
      # Only the engagement's key user has one here; other managers come in by
      # their own link.
      class KeyPersonSessionsController < BaseController
        include KeyPersonConversationEndpoints

        before_action :require_key_user!

        private

        def key_participant
          @key_participant ||= current_company.current_engagement.participants.find_by!(source: "KEY_USER")
        end

        def require_key_user!
          engagement = current_company.current_engagement
          return if engagement && engagement.key_user_id == current_company_user.id

          render json: { error: "Only the engagement's key user has this conversation." }, status: :forbidden
        end
      end
    end
  end
end
