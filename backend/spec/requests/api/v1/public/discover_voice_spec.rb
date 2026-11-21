# frozen_string_literal: true

require 'rails_helper'

# Server side of the live avatar interview. Providers are stubbed here, so these
# examples check access control and credential handling only — not the real-time
# experience (see frontend e2e/liveavatar-page-mocked.spec.ts).
RSpec.describe 'Api::V1::Public::DiscoverVoice', type: :request do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, onboarding_step: 'verified', participation_status: 'started') }
  let!(:session) { create(:employee_web_session, employee: employee, company: company, verified_at: Time.current) }
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) { create(:conversation, employee: employee, company: company, status: 'discovery', question_count: 1) }

  # The avatar's lines come from the shared instructions file; these examples
  # assert the built-in wording, whatever the operator has configured.
  around do |example|
    saved = ENV['INTERVIEWER_INSTRUCTIONS_PATH']
    ENV['INTERVIEWER_INSTRUCTIONS_PATH'] = Rails.root.join('tmp', 'no-interviewer-instructions.yaml').to_s
    Voice::InterviewerPhrases.reset!
    example.run
  ensure
    saved.nil? ? ENV.delete('INTERVIEWER_INSTRUCTIONS_PATH') : ENV['INTERVIEWER_INSTRUCTIONS_PATH'] = saved
    Voice::InterviewerPhrases.reset!
  end

  before do
    Rails.cache.clear
  end

  it 'requires the employee session and an open interview, and rate-limits sessions' do
    la_client = instance_double(LiveAvatar::Client, stop_session: true)
    allow(LiveAvatar::Client).to receive(:new).and_return(la_client)
    allow(LiveAvatar::Client).to receive(:configured?).and_return(true)
    allow(la_client).to receive(:create_session).and_return(
      LiveAvatar::Client::Session.new(session_id: 's', session_token: 't', mode: 'FULL', sandbox: false, max_session_duration: nil))
    post '/api/v1/public/discover/voice/session'
    expect(response).to have_http_status(:unauthorized)
    conversation.update!(status: 'completed')
    post '/api/v1/public/discover/voice/session', headers: headers
    expect(response).to have_http_status(:conflict)
    conversation.update!(status: 'discovery')
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) # production uses Redis
    statuses = Array.new(9) { post('/api/v1/public/discover/voice/session', headers: headers) && response.status }
    expect(statuses.last).to eq(429)
  end

  describe 'LiveAvatar (mocked: no LiveAvatar request, session or credit)' do
    let(:live) do
      LiveAvatar::Client::Session.new(session_id: 'la-sess-1', session_token: 'la-token', mode: 'FULL', sandbox: false,
                                      max_session_duration: nil)
    end
    let(:la_client) { instance_double(LiveAvatar::Client) }

    before do
      allow(LiveAvatar::Client).to receive(:new).and_return(la_client)
      allow(LiveAvatar::Client).to receive(:configured?).and_return(true)
      allow(la_client).to receive(:stop_session).and_return(true)
      stub_const('ENV', ENV.to_h.merge('LIVEAVATAR_API_KEY' => 'la-secret-key', 'SIMLI_API_KEY' => 'simli-secret-key'))
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it 'issues a FULL session token (never the key) and the fixed texts June speaks' do
      allow(la_client).to receive(:create_session).and_return(live)
      post '/api/v1/public/discover/voice/session', headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('provider' => 'liveavatar', 'display_name' => be_present,
                              'liveavatar' => include('session_token' => 'la-token', 'session_id' => 'la-sess-1', 'mode' => 'FULL'))
      expect(body.dig('texts', 'acknowledgements').first).to eq('Thank you.')
      expect(body.dig('texts', 'phrases', 'greeting')).to start_with('Hi, thanks for joining')
      expect(response.body).not_to include('la-secret-key', 'simli')
      expect(body.keys).not_to include('transcription', 'simli', 'simli_available')
    end

    it 'ignores any request for LITE or another avatar: one LiveAvatar FULL session' do
      expect(la_client).to receive(:create_session).with(language: anything).and_return(live)
      post '/api/v1/public/discover/voice/session', params: { liveavatar_mode: 'LITE', fallback: 'simli' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key('simli')
    end

    it 'reports a LiveAvatar refusal as a retryable error and never substitutes another avatar' do
      allow(la_client).to receive(:create_session).and_raise(LiveAvatar::Client::Error, 'LiveAvatar refused /v1/sessions/token (HTTP 402): no credits')
      post '/api/v1/public/discover/voice/session', headers: headers
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'LiveAvatar refused /v1/sessions/token (HTTP 402): no credits', 'retryable' => true)
    end

    it 'says clearly when LiveAvatar is not configured' do
      allow(LiveAvatar::Client).to receive(:configured?).and_return(false)
      expect(la_client).not_to receive(:create_session)
      post '/api/v1/public/discover/voice/session', headers: headers
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include('retryable' => false)
    end

    it "stops the employee's previous LiveAvatar session on restart and on the stop backstop" do
      allow(la_client).to receive(:create_session).and_return(live)
      post '/api/v1/public/discover/voice/session', headers: headers
      expect(la_client).not_to have_received(:stop_session)
      post '/api/v1/public/discover/voice/session', headers: headers
      expect(la_client).to have_received(:stop_session).with('la-sess-1').once
      post '/api/v1/public/discover/voice/session/stop', headers: headers
      expect(la_client).to have_received(:stop_session).with('la-sess-1').twice
      expect(response.parsed_body).to eq('stopped' => true)
      post '/api/v1/public/discover/voice/session/stop', headers: headers
      expect(response.parsed_body).to eq('stopped' => false) # nothing left to stop
      post '/api/v1/public/discover/voice/session/stop'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
