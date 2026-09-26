# frozen_string_literal: true

module Api
  module V1
    module Public
      # GET /api/v1/public/discover/messages/:id/speech — an interview question,
      # spoken, for the web interview's read-aloud. Only the interviewer's own
      # messages in the employee's own conversation, so it can never read out
      # anything the employee could not already see.
      class DiscoverSpeechController < ApplicationController
        include EmployeeWebAuthenticatable

        def show
          message = visible_messages.where(direction: "outbound").find(params[:id])
          return head :not_found if message.body.blank?

          client = Openai::Client.new
          unless client.speech_available?
            return render json: { error: "Speech is not available" }, status: :service_unavailable
          end

          # A question is spoken once; replaying it is served from the cache.
          audio = Rails.cache.fetch(["discover-speech", message.id, Digest::SHA1.hexdigest(message.body)],
                                    expires_in: 7.days) do
            client.speech(text: message.body)
          end
          send_data audio, type: "audio/mpeg", disposition: "inline"
        rescue Openai::Client::Error => e
          Rails.logger.warn("[DiscoverSpeech] #{e.message}")
          render json: { error: "Speech is not available right now" }, status: :service_unavailable
        end
      end
    end
  end
end
