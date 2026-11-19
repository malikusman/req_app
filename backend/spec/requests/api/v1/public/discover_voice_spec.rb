# frozen_string_literal: true

require 'rails_helper'

# Server side of the live avatar interview. Providers are stubbed here, so these
# examples check access control, credential handling and streaming plumbing only —
# not the real-time experience (see frontend e2e/avatar-live.spec.ts).
RSpec.describe 'Api::V1::Public::DiscoverVoice', type: :request do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, onboarding_step: 'verified', participation_status: 'started') }
  let!(:session) { create(:employee_web_session, employee: employee, company: company, verified_at: Time.current) }
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) { create(:conversation, employee: employee, company: company, status: 'discovery', question_count: 1) }

  before do
    Rails.cache.clear
    Voice::PhraseAudioCache.clear
  end

  it 'issues only short-lived browser credentials, never the provider keys' do
    allow(Voice::AvatarSession).to receive(:simli_token).and_return(session_token: 'simli-session', face_id: 'face-1')
    allow(Voice::AvatarSession).to receive(:transcription_secret).and_return(client_secret: 'ek_test', expires_at: 1, webrtc_url: 'https://api.openai.com/v1/realtime/calls')
    stub_const('ENV', ENV.to_h.merge('SIMLI_API_KEY' => 'simli-secret-key', 'OPENAI_API_KEY' => 'sk-test-secret-key-0000000000'))
    post '/api/v1/public/discover/voice/session', headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('simli' => include('session_token' => 'simli-session'),
                                            'transcription' => include('client_secret' => 'ek_test'))
    expect(response.body).not_to include('simli-secret-key', 'sk-test-secret-key')
  end

  it 'reports a provider outage per component so the page can fall back' do
    allow(Voice::AvatarSession).to receive(:simli_token).and_raise(Voice::AvatarSession::Error, 'api.simli.ai refused the session (HTTP 402)')
    allow(Voice::AvatarSession).to receive(:transcription_secret).and_return(client_secret: 'ek_test', expires_at: 1, webrtc_url: 'x')
    post '/api/v1/public/discover/voice/session', headers: headers
    expect(response.parsed_body).to include('simli_error' => include('402'), 'transcription' => be_present)
    expect(response.parsed_body).not_to have_key('simli')
  end

  it 'requires the employee session and an open interview, and rate-limits sessions' do
    post '/api/v1/public/discover/voice/session'
    expect(response).to have_http_status(:unauthorized)
    conversation.update!(status: 'completed')
    post '/api/v1/public/discover/voice/session', headers: headers
    expect(response).to have_http_status(:conflict)
    conversation.update!(status: 'discovery')
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) # production uses Redis
    allow(Voice::AvatarSession).to receive(:simli_token).and_return(session_token: 't', face_id: 'f')
    allow(Voice::AvatarSession).to receive(:transcription_secret).and_return(client_secret: 'ek', expires_at: 1, webrtc_url: 'x')
    statuses = Array.new(9) { post('/api/v1/public/discover/voice/session', headers: headers) && response.status }
    expect(statuses.last).to eq(429)
  end

  it 'speaks only this employee\'s interviewer messages and fixed phrases' do
    mine = create(:message, conversation: conversation, direction: 'outbound', track: 'discovery', body: "• Weekly report: every Monday; 1–2 hours")
    other = create(:conversation, company: company, employee: create(:employee, company: company), status: 'discovery')
    theirs = create(:message, conversation: other, direction: 'outbound', track: 'discovery', body: 'Private question')
    answer = create(:message, conversation: conversation, direction: 'inbound', track: 'discovery', body: 'My own answer')
    spoken = []
    client = instance_double(Openai::Client, speech_available?: true)
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(client).to receive(:speech_stream) { |text:, &block| spoken << text; block.call("\x01\x02".b) }

    get "/api/v1/public/discover/voice/speech?message_id=#{mine.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(spoken.last).to eq('Weekly report: every Monday; 1 to 2 hours')
    get "/api/v1/public/discover/voice/speech?phrase=greeting", headers: headers
    expect(spoken.last).to start_with('Hi, thanks for joining')
    get "/api/v1/public/discover/voice/speech?acknowledgement=1", headers: headers
    expect(spoken.last).to eq('Okay, thanks.')

    [theirs.id, answer.id].each do |id|
      get "/api/v1/public/discover/voice/speech?message_id=#{id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
    get '/api/v1/public/discover/voice/speech?phrase=anything', headers: headers
    expect(response).to have_http_status(:not_found)
    expect(spoken.size).to eq(3)
  end

  it 'reuses synthesised audio for fixed phrases but never for interview questions' do
    question = create(:message, conversation: conversation, direction: 'outbound', track: 'discovery', body: 'What do you do on Mondays?')
    client = instance_double(Openai::Client, speech_available?: true)
    allow(Openai::Client).to receive(:new).and_return(client)
    calls = Hash.new(0)
    allow(client).to receive(:speech_stream) { |text:, &block| calls[text] += 1; block.call("".b); block.call("".b) }

    2.times do
      get '/api/v1/public/discover/voice/speech?acknowledgement=0', headers: headers
      expect(response.body.b).to eq("".b)
      get "/api/v1/public/discover/voice/speech?message_id=#{question.id}", headers: headers
      expect(response.body.b).to eq("".b)
    end
    expect(calls).to eq('Thank you.' => 1, 'What do you do on Mondays?' => 2)
  end

  it 'does not cache a fixed phrase whose synthesis failed part-way' do
    client = instance_double(Openai::Client, speech_available?: true)
    allow(Openai::Client).to receive(:new).and_return(client)
    attempts = 0
    allow(client).to receive(:speech_stream) do |text:, &block|
      attempts += 1
      block.call("".b)
      raise Openai::Client::Error, 'speech failed (HTTP 500)' if attempts == 1
    end
    2.times { get '/api/v1/public/discover/voice/speech?phrase=greeting', headers: headers }
    expect(attempts).to eq(2)
  end
end
