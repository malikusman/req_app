# frozen_string_literal: true

module Api
  module V1
    module Public
      # A manager's conversation with leadership, reached by the signed link in
      # their invitation (Doc 14 §4.3). The link is the only key: it opens this
      # one person's conversation and nothing else in the platform.
      class KeyPersonSessionsController < ApplicationController
        include KeyPersonConversationEndpoints

        before_action :find_participant

        private

        def key_participant = @participant

        def find_participant
          @participant = KeyPerson::Invite.participant_for(params[:token])
          return if @participant

          render json: { error: "This link has expired or isn't valid. Ask the person who invited you for a new one." },
                 status: :unauthorized
        end
      end
    end
  end
end
