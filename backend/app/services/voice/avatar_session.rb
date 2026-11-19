# frozen_string_literal: true

require "net/http"

module Voice
  # Short-lived browser credentials for the real-time avatar interview. API keys
  # never leave the server: Simli receives a session token for one avatar session,
  # and OpenAI an ephemeral client secret for one transcription session.
  #
  # Simli renders a lip-synced avatar from audio we send (PCM16, 16 kHz, mono). It
  # does not transcribe, think or speak on its own — speech-to-text and turn
  # detection come from OpenAI Realtime transcription, the interview itself from the
  # existing Employee Discovery V2 engine, and the voice from OpenAI speech.
  class AvatarSession
    class Error < StandardError; end

    SIMLI_TOKEN_URL = "https://api.simli.ai/compose/token"
    REALTIME_SECRET_URL = "https://api.openai.com/v1/realtime/client_secrets"

    def self.simli_configured?
      ENV["SIMLI_API_KEY"].present? && ENV["SIMLI_FACE_ID"].present?
    end

    # The interview is at most ~25 minutes; idle avatars end themselves.
    def self.simli_token
      raise Error, "Simli is not configured" unless simli_configured?

      body = { faceId: ENV.fetch("SIMLI_FACE_ID"), handleSilence: true,
               maxSessionLength: ENV.fetch("SIMLI_MAX_SESSION_SECONDS", "1800").to_i,
               maxIdleTime: ENV.fetch("SIMLI_MAX_IDLE_SECONDS", "300").to_i }
      json = post(SIMLI_TOKEN_URL, body, "x-simli-api-key" => ENV.fetch("SIMLI_API_KEY"))
      token = json["session_token"]
      raise Error, "Simli did not issue a session token" if token.blank? || token == "FAIL TOKEN"

      { session_token: token, face_id: ENV.fetch("SIMLI_FACE_ID") }
    end

    def self.transcription_secret(language:)
      key = ENV["OPENAI_API_KEY"].presence
      raise Error, "OpenAI is not configured" unless key

      input = {
        transcription: { model: ENV.fetch("OPENAI_REALTIME_STT_MODEL", "gpt-4o-mini-transcribe"),
                         language: language.to_s[0, 2].presence },
        # Semantic VAD waits for the speaker to finish a thought rather than the
        # first pause, so natural hesitation does not cut an answer in half.
        turn_detection: { type: "semantic_vad", eagerness: ENV.fetch("VOICE_VAD_EAGERNESS", "low") },
        noise_reduction: { type: "near_field" }
      }
      input[:transcription].compact!
      json = post(REALTIME_SECRET_URL, { expires_after: { anchor: "created_at", seconds: 600 },
                                         session: { type: "transcription", audio: { input: input } } },
                  "Authorization" => "Bearer #{key}")
      raise Error, "OpenAI did not issue a transcription secret" if json["value"].blank?

      { client_secret: json["value"], expires_at: json["expires_at"], webrtc_url: "https://api.openai.com/v1/realtime/calls" }
    end

    def self.post(url, body, headers)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      headers.merge("Content-Type" => "application/json").each { |k, v| request[k] = v }
      request.body = body.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        # Provider error bodies may echo request details; log only the status.
        raise Error, "#{uri.host} refused the session (HTTP #{response.code})"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Error, "#{uri.host} unavailable (#{e.class.name})"
    end
  end
end
