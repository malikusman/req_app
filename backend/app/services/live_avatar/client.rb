# frozen_string_literal: true

require "net/http"

module LiveAvatar
  # Server-side wrapper over the LiveAvatar session API (https://docs.liveavatar.com)
  # for the real-time avatar interview. The API key never leaves Rails: the browser
  # only receives a session token scoped to one session.
  #
  # One mode only: FULL, in LiveAvatar's documented restricted mode. LiveAvatar
  # runs the media pipeline (microphone, voice activity detection, transcription,
  # June HR's own voice and lip-sync). We deliberately send NO context and NO LLM
  # configuration: "If no context is supplied, the avatar operates in restricted
  # mode - it will not respond to user input. User transcripts are still emitted"
  # (docs: FULL mode / configuration). The Employee Discovery V2 engine writes
  # every question and the browser sends it with `avatar.speak_text`.
  #
  # LITE was dropped: it needs a second speech-to-text and text-to-speech pipeline
  # in the browser for no gain in control, since the engine is authoritative in
  # FULL restricted mode already.
  #
  # Env:
  #   LIVEAVATAR_API_KEY                       required
  #   LIVEAVATAR_AVATAR_ID                     required unless sandbox (June HR)
  #   LIVEAVATAR_SANDBOX=true                  free ~1-minute sessions, sandbox avatar only
  #   LIVEAVATAR_VOICE_ID                      optional voice override
  #   LIVEAVATAR_LANGUAGE                      optional language override (default: employee's)
  #   LIVEAVATAR_MAX_SESSION_DURATION_SECONDS  optional; must not exceed the plan's limit
  #   LIVEAVATAR_VIDEO_QUALITY                 optional: very_high | high | medium | low
  #   LIVEAVATAR_API_URL                       optional override
  class Client
    class Error < StandardError; end

    DEFAULT_API_URL = "https://api.liveavatar.com"
    # The only avatar sandbox sessions may use (docs: Sandbox Mode).
    SANDBOX_AVATAR_ID = "dd73ea75-1218-4ef3-92ce-606d5f7fbc0a"
    MODE = "FULL"
    VIDEO_QUALITIES = %w[very_high high medium low].freeze
    # Fields that would hand the conversation to a LiveAvatar-side LLM. Never sent.
    FORBIDDEN_FIELDS = %i[context_id llm_configuration_id llm_settings voice_agent openai_realtime_config
                          gemini_realtime_config elevenlabs_agent_config cartesia_agent_config].freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    Session = Struct.new(:session_id, :session_token, :mode, :sandbox, :max_session_duration, keyword_init: true)

    class << self
      def sandbox?
        ENV["LIVEAVATAR_SANDBOX"].to_s.strip.casecmp?("true")
      end

      def configured?
        ENV["LIVEAVATAR_API_KEY"].present? && (sandbox? || ENV["LIVEAVATAR_AVATAR_ID"].present?)
      end

      def max_session_duration
        value = ENV["LIVEAVATAR_MAX_SESSION_DURATION_SECONDS"].to_s.strip
        value.match?(/\A\d+\z/) && value.to_i.positive? ? value.to_i : nil
      end
    end

    # Mints a session token. Nothing starts or bills until the browser's SDK
    # starts the session with it.
    def create_session(language: nil)
      raise Error, "LiveAvatar is not configured" unless self.class.configured?

      data = post("/v1/sessions/token", token_body(language: language))
      session_id = data["session_id"].to_s
      session_token = data["session_token"].to_s
      raise Error, "LiveAvatar returned no session token" if session_id.blank? || session_token.blank?

      Session.new(session_id: session_id, session_token: session_token, mode: MODE, sandbox: self.class.sandbox?,
                  max_session_duration: self.class.max_session_duration)
    end

    # Stops a session with the API key: the backstop for a browser that closed
    # without stopping its own. Already-ended sessions are not an error.
    def stop_session(session_id, reason: "USER_CLOSED")
      return false if session_id.blank?

      post("/v1/sessions/stop", { session_id: session_id, reason: reason })
      true
    rescue Error => e
      Rails.logger.info("[LiveAvatar] stop #{session_id.to_s.first(8)}: #{e.message}")
      false
    end

    def token_body(language: nil)
      body = { mode: MODE, avatar_id: avatar_id }
      body[:is_sandbox] = true if self.class.sandbox?
      duration = self.class.max_session_duration
      body[:max_session_duration] = duration if duration
      quality = ENV["LIVEAVATAR_VIDEO_QUALITY"].to_s.strip
      body[:video_settings] = { quality: quality } if VIDEO_QUALITIES.include?(quality)
      # CONVERSATIONAL keeps LiveAvatar's own voice activity detection and
      # barge-in. FULL requires exactly one of avatar_persona / voice_agent (HTTP
      # 422 otherwise); a persona without context_id is restricted mode.
      body[:interactivity_type] = "CONVERSATIONAL"
      body[:avatar_persona] = full_persona(language)
      leaked = FORBIDDEN_FIELDS & (body.keys + body[:avatar_persona].keys)
      raise Error, "refusing to give LiveAvatar control of the conversation (#{leaked.join(', ')})" if leaked.any?

      body
    end

    private

    # Voice and language only: no context_id, so the avatar stays in LiveAvatar's
    # documented restricted mode ("it will not respond to user input") and never
    # generates replies of its own. Without voice_id LiveAvatar uses the avatar's
    # own default voice (June HR's voice for the June HR avatar).
    def full_persona(language)
      persona = { language: ENV["LIVEAVATAR_LANGUAGE"].presence || language.to_s[0, 2].presence || "en" }
      persona[:voice_id] = ENV["LIVEAVATAR_VOICE_ID"].strip if ENV["LIVEAVATAR_VOICE_ID"].present?
      persona
    end

    def avatar_id
      self.class.sandbox? ? SANDBOX_AVATAR_ID : ENV.fetch("LIVEAVATAR_AVATAR_ID")
    end

    def post(path, body)
      uri = URI("#{api_url}#{path}")
      request = Net::HTTP::Post.new(uri)
      request["X-API-KEY"] = ENV.fetch("LIVEAVATAR_API_KEY")
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = body.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
      parsed = JSON.parse(response.body.presence || "{}")
      unless response.is_a?(Net::HTTPSuccess)
        # The provider's message names the problem (bad avatar, no credits, a
        # duration above the plan's limit); the key is never part of it.
        raise Error, "LiveAvatar refused #{path} (HTTP #{response.code}): #{parsed['message'].to_s.truncate(200)}"
      end

      parsed["data"] || {}
    rescue JSON::ParserError
      raise Error, "LiveAvatar #{path} returned an unreadable response"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
      raise Error, "LiveAvatar #{path} unreachable (#{e.class.name})"
    end

    def api_url
      ENV.fetch("LIVEAVATAR_API_URL", DEFAULT_API_URL).chomp("/")
    end
  end
end
