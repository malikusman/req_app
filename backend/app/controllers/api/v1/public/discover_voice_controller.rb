# frozen_string_literal: true

module Api
  module V1
    module Public
      # Real-time avatar interview support. The interview itself still runs through
      # POST/GET discover/messages and the Employee Discovery V2 engine; this
      # controller only issues short-lived media credentials and streams speech.
      class DiscoverVoiceController < ApplicationController
        include EmployeeWebAuthenticatable

        SESSION_LIMIT = 8 # avatar sessions per employee per 10 minutes
        # Fixed wording only: spoken while the engine works, so it asserts nothing
        # about what the employee said and never replaces an engine question.
        ACKNOWLEDGEMENTS = ["Thank you.", "Okay, thanks.", "Got it, thank you.", "Thanks, one moment."].freeze
        PHRASES = {
          "greeting" => "Hi, thanks for joining. I'll ask you a few questions about your work. Just answer out loud, in your own words, and take your time.",
          "rephrase" => "Sorry, I couldn't record that properly. Could you say it again, maybe in slightly different words?",
          "still_working" => "Thanks. I'm still noting your last answer, one moment.",
          "resumed" => "Welcome back. Let's carry on."
        }.freeze

        # POST /api/v1/public/discover/voice/session
        def session_create
          unless %w[onboarding profiling discovery].include?(current_conversation.status)
            return render json: { error: "This interview is not open for a live session" }, status: :conflict
          end
          key = "discover-voice-sessions:#{current_employee.id}"
          count = Rails.cache.increment(key, 1, expires_in: 10.minutes) || 1
          return render json: { error: "Too many live sessions. Please wait a few minutes." }, status: :too_many_requests if count > SESSION_LIMIT

          language = current_employee.preferred_language.presence || current_employee.company.locale
          result = { language: language, acknowledgements: ACKNOWLEDGEMENTS.size, phrases: PHRASES.keys,
                     speech: { format: "pcm16", sample_rate: 24_000, available: Openai::Client.new.speech_available? } }
          begin
            result[:transcription] = Voice::AvatarSession.transcription_secret(language: language)
          rescue Voice::AvatarSession::Error => e
            result[:transcription_error] = e.message
          end
          begin
            result[:simli] = Voice::AvatarSession.simli_token
          rescue Voice::AvatarSession::Error => e
            result[:simli_error] = e.message
          end
          Rails.logger.info("[DiscoverVoice] session employee=#{current_employee.id} simli=#{result[:simli].present?} stt=#{result[:transcription].present?}")
          render json: result
        end

        # GET /api/v1/public/discover/voice/speech?message_id=… | ?acknowledgement=0..3
        # Raw PCM16 24 kHz mono, streamed as it is synthesised.
        def speech
          text = speech_text
          return head :not_found if text.blank?

          client = Openai::Client.new
          return head :service_unavailable unless client.speech_available?

          # A Rack streaming body: Puma writes each chunk as OpenAI produces it, so
          # the avatar starts speaking ~1 s after the request instead of after the
          # whole sentence. (ActionController::Live's extra thread stalled behind
          # the reload interlock in development and delayed first audio by ~7 s.)
          headers["Content-Type"] = "application/octet-stream"
          headers["Cache-Control"] = "no-cache, no-store"
          headers["X-Accel-Buffering"] = "no"
          headers["Last-Modified"] = Time.now.httpdate # Rack::ETag must not buffer the body
          fixed = fixed_phrase?
          cached = fixed && Voice::PhraseAudioCache.read(text)
          self.response_body = Enumerator.new do |out|
            if cached
              Voice::PhraseAudioCache.each_slice(cached) { |chunk| out << chunk }
            else
              audio = fixed ? +"".b : nil
              client.speech_stream(text: text) { |chunk| out << chunk; audio&.<<(chunk.b) }
              # Only a complete synthesis is reused.
              Voice::PhraseAudioCache.write(text, audio) if audio
            end
          rescue Openai::Client::Error, IOError, Errno::EPIPE => e
            Rails.logger.warn("[DiscoverVoice] speech stream ended: #{e.class.name}")
          end
        end

        private

        # Acknowledgements and fixed phrases: the same words for every employee.
        def fixed_phrase?
          params[:acknowledgement].present? || params[:phrase].present?
        end

        def speech_text
          if params[:acknowledgement].present?
            index = Integer(params[:acknowledgement], exception: false)
            return index && ACKNOWLEDGEMENTS[index]
          end
          return PHRASES[params[:phrase].to_s] if params[:phrase].present?

          # Only the interviewer's own messages in this employee's conversation.
          spoken(visible_messages.where(direction: "outbound").find_by(id: params[:message_id])&.body)
        end

        # The caption shows the exact text; the voice reads it naturally.
        def spoken(text)
          return nil if text.blank?

          text.gsub(/^\s*[•\-*]\s*/, "").gsub(/(\d)\s*[–—-]\s*(\d)/, '\1 to \2').gsub(/\s*\n+\s*/, ". ").squeeze(" ")
              .gsub(/\.\s*\./, ".").gsub(/:\s*\./, ":")
        end
      end
    end
  end
end
