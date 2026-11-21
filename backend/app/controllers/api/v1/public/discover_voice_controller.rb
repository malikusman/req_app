# frozen_string_literal: true

module Api
  module V1
    module Public
      # Real-time avatar interview support. The interview itself still runs through
      # POST/GET discover/messages and the Employee Discovery V2 engine; this
      # controller only issues and stops short-lived LiveAvatar sessions.
      class DiscoverVoiceController < ApplicationController
        include EmployeeWebAuthenticatable

        SESSION_LIMIT = 8 # avatar sessions per employee per 10 minutes
        # Fixed wording only (greeting, acknowledgements...): spoken while the engine
        # works, so it asserts nothing about what the employee said and never
        # replaces an engine question. Configured in the interviewer instructions
        # file (avatar section); see Voice::InterviewerPhrases.

        # POST /api/v1/public/discover/voice/session
        #
        # One avatar architecture: LiveAvatar FULL (June HR) in restricted mode.
        # LiveAvatar listens (mic, VAD, transcription) and voices text; the V2
        # engine writes every word. There is no other avatar provider and no
        # silent substitute: if LiveAvatar refuses, the reason is returned with a
        # 503 and the page shows it with a retry button.
        def session_create
          unless %w[onboarding profiling discovery].include?(current_conversation.status)
            return render json: { error: "This interview is not open for a live session" }, status: :conflict
          end
          unless LiveAvatar::Client.configured?
            return render json: { error: "The live interviewer is not configured on this server", retryable: false },
                          status: :service_unavailable
          end
          key = "discover-voice-sessions:#{current_employee.id}"
          count = Rails.cache.increment(key, 1, expires_in: 10.minutes) || 1
          return render json: { error: "Too many live sessions. Please wait a few minutes." }, status: :too_many_requests if count > SESSION_LIMIT

          language = current_employee.preferred_language.presence || current_employee.company.locale
          stop_previous_liveavatar
          begin
            live = LiveAvatar::Client.new.create_session(language: language)
          rescue LiveAvatar::Client::Error => e
            Rails.logger.warn("[DiscoverVoice] LiveAvatar unavailable employee=#{current_employee.id}: #{e.message}")
            return render json: { error: e.message, retryable: true }, status: :service_unavailable
          end
          Rails.cache.write(liveavatar_cache_key, live.session_id, expires_in: 2.hours)
          Rails.logger.info("[DiscoverVoice] session employee=#{current_employee.id} liveavatar=#{live.mode} sandbox=#{live.sandbox}")
          render json: {
            language: language,
            provider: "liveavatar",
            display_name: Voice::InterviewerPhrases.display_name,
            instructions_version: Voice::InterviewerPhrases.version,
            # Fixed lines the avatar speaks itself (greeting, backchannels...).
            texts: { acknowledgements: Voice::InterviewerPhrases.acknowledgements, phrases: Voice::InterviewerPhrases.phrases },
            liveavatar: { session_token: live.session_token, session_id: live.session_id, mode: live.mode,
                          sandbox: live.sandbox, max_session_duration: live.max_session_duration }
          }
        end

        # POST /api/v1/public/discover/voice/session/stop
        # Backstop: the browser stops its own LiveAvatar session, but a closed tab
        # may not; this stops it with the API key so no credits run on.
        def session_stop
          stopped = stop_previous_liveavatar
          render json: { stopped: stopped }
        end

        private

        def liveavatar_cache_key
          "discover-voice-liveavatar:#{current_employee.id}"
        end

        # Only the session this employee started; never one named by the browser.
        def stop_previous_liveavatar
          session_id = Rails.cache.read(liveavatar_cache_key)
          return false if session_id.blank?

          Rails.cache.delete(liveavatar_cache_key)
          LiveAvatar::Client.configured? && LiveAvatar::Client.new.stop_session(session_id)
        end
      end
    end
  end
end
