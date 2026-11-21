# frozen_string_literal: true

require "rails_helper"

# LiveAvatar is stubbed at the HTTP layer: no request leaves the test process,
# no session starts and no credits are used.
RSpec.describe LiveAvatar::Client do
  let(:avatar_id) { "11111111-2222-3333-4444-555555555555" }
  let(:env) { { "LIVEAVATAR_API_KEY" => "test-la-key", "LIVEAVATAR_AVATAR_ID" => avatar_id } }
  let(:token_url) { "https://api.liveavatar.com/v1/sessions/token" }

  around do |example|
    keys = %w[LIVEAVATAR_API_KEY LIVEAVATAR_AVATAR_ID LIVEAVATAR_SANDBOX LIVEAVATAR_MODE LIVEAVATAR_VOICE_ID
              LIVEAVATAR_LANGUAGE LIVEAVATAR_MAX_SESSION_DURATION_SECONDS LIVEAVATAR_VIDEO_QUALITY LIVEAVATAR_API_URL]
    saved = keys.to_h { |k| [k, ENV[k]] }
    keys.each { |k| ENV.delete(k) }
    env.each { |k, v| ENV[k] = v }
    WebMock.disable_net_connect!
    example.run
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def token_response(id: "sess-1", token: "jwt-1")
    { status: 200, body: { code: 1000, data: { session_id: id, session_token: token } }.to_json,
      headers: { "Content-Type" => "application/json" } }
  end

  describe ".configured?" do
    it "needs a key and an avatar (or sandbox)" do
      expect(described_class.configured?).to be(true)
      ENV.delete("LIVEAVATAR_AVATAR_ID")
      expect(described_class.configured?).to be(false)
      ENV["LIVEAVATAR_SANDBOX"] = "true"
      expect(described_class.configured?).to be(true)
      ENV.delete("LIVEAVATAR_API_KEY")
      expect(described_class.configured?).to be(false)
    end
  end

  describe "#create_session" do
    it "mints a FULL token in restricted mode: no context and no LLM, so the engine stays authoritative" do
      # LiveAvatar answers HTTP 422 ("Provide exactly one of avatar_persona or
      # voice_agent") when FULL has neither, so avatar_persona is always sent.
      stub = stub_request(:post, token_url)
             .with(headers: { "X-API-KEY" => "test-la-key" },
                   body: { mode: "FULL", avatar_id: avatar_id, interactivity_type: "CONVERSATIONAL",
                           avatar_persona: { language: "en" } }.to_json)
             .to_return(token_response)

      session = described_class.new.create_session(language: "en")

      expect(stub).to have_been_requested
      expect(session.to_h).to include(session_id: "sess-1", session_token: "jwt-1", mode: "FULL", sandbox: false)
    end

    it "never sends a context, LLM or voice-agent field in FULL mode" do
      ENV["LIVEAVATAR_VOICE_ID"] = "voice-1"
      body = described_class.new.token_body(language: "fr")
      expect(body[:avatar_persona]).to eq(language: "fr", voice_id: "voice-1")
      expect(body).not_to have_key(:voice_agent) # exactly one of avatar_persona / voice_agent
      flat = body.to_json
      %w[context_id llm_configuration_id llm_settings voice_agent openai_realtime_config].each do |field|
        expect(flat).not_to include(field)
      end
    end

    it "always sends avatar_persona in FULL, defaulting to English and the avatar's own voice" do
      [nil, "", "en"].each do |language|
        body = described_class.new.token_body(language: language)
        expect(body[:avatar_persona]).to eq(language: "en")
      end
      ENV["LIVEAVATAR_LANGUAGE"] = "ar"
      expect(described_class.new.token_body(language: "en")[:avatar_persona]).to eq(language: "ar")
    end

    it "is FULL only: LIVEAVATAR_MODE=LITE no longer changes the session" do
      ENV["LIVEAVATAR_MODE"] = "LITE"
      stub = stub_request(:post, token_url).with(body: hash_including("mode" => "FULL")).to_return(token_response)
      expect(described_class.new.create_session.mode).to eq("FULL")
      expect(stub).to have_been_requested
    end

    it "uses the sandbox avatar, a duration cap and video quality when configured" do
      ENV["LIVEAVATAR_SANDBOX"] = "true"
      ENV["LIVEAVATAR_MAX_SESSION_DURATION_SECONDS"] = "900"
      ENV["LIVEAVATAR_VIDEO_QUALITY"] = "medium"
      stub = stub_request(:post, token_url)
             .with(body: hash_including("avatar_id" => described_class::SANDBOX_AVATAR_ID, "is_sandbox" => true,
                                        "max_session_duration" => 900, "video_settings" => { "quality" => "medium" }))
             .to_return(token_response)
      session = described_class.new.create_session
      expect(stub).to have_been_requested
      expect(session.sandbox).to be(true)
      expect(session.max_session_duration).to eq(900)
    end

    it "reports refusals and outages without leaking the key" do
      stub_request(:post, token_url).to_return(status: 402, body: { code: 4002, message: "Insufficient credits" }.to_json)
      expect { described_class.new.create_session }.to raise_error(described_class::Error, /HTTP 402.*Insufficient credits/) { |e|
        expect(e.message).not_to include("test-la-key")
      }
      stub_request(:post, token_url).to_timeout
      expect { described_class.new.create_session }.to raise_error(described_class::Error, /unreachable/)
      stub_request(:post, token_url).to_return(status: 200, body: { code: 1000, data: {} }.to_json)
      expect { described_class.new.create_session }.to raise_error(described_class::Error, /no session token/)
    end

    it "refuses to mint anything when not configured" do
      ENV.delete("LIVEAVATAR_API_KEY")
      expect { described_class.new.create_session }.to raise_error(described_class::Error, /not configured/)
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  describe "#stop_session" do
    it "stops with the API key and tolerates an already-ended session" do
      stub = stub_request(:post, "https://api.liveavatar.com/v1/sessions/stop")
             .with(headers: { "X-API-KEY" => "test-la-key" }, body: { session_id: "sess-1", reason: "USER_CLOSED" }.to_json)
             .to_return(status: 200, body: { code: 1000, data: nil }.to_json)
      expect(described_class.new.stop_session("sess-1")).to be(true)
      expect(stub).to have_been_requested

      stub_request(:post, "https://api.liveavatar.com/v1/sessions/stop").to_return(status: 404, body: "{}")
      expect(described_class.new.stop_session("sess-1")).to be(false)
      expect(described_class.new.stop_session(nil)).to be(false)
    end
  end
end
