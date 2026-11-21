# frozen_string_literal: true

require 'rails_helper'

# Web consent for the avatar interview: a plain statement and a button instead of
# the WhatsApp "reply YES" exchange, with the same effects as a YES.
RSpec.describe 'Api::V1::Public::DiscoverConsent', type: :request do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, onboarding_step: 'awaiting_consent', participation_status: 'started',
                      department: nil, role_title: nil, preferred_language: nil)
  end
  let!(:session) { create(:employee_web_session, employee: employee, company: company, verified_at: Time.current) }
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) { create(:conversation, employee: employee, company: company, status: 'onboarding', question_count: 0) }

  before do
    company.update!(settings: (company.settings || {}).merge('discovery_profiling_enabled' => true))
    Voice::InterviewerPhrases.reset!
  end

  it 'shows web wording (no WhatsApp instructions) and a version tied to that wording' do
    get '/api/v1/public/discover/consent', headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['required']).to be(true)
    expect(body['text']).to be_present
    expect(body['text']).not_to match(/whatsapp|reply yes|reply stop/i)
    expect(body['version']).to eq("web-avatar-#{Digest::SHA256.hexdigest(body['text'])[0, 12]}")
  end

  it 'records consent and starts the interview exactly like a YES, without any spoken or typed answer' do
    get '/api/v1/public/discover/consent', headers: headers
    version = response.parsed_body['version']

    post '/api/v1/public/discover/consent', params: { version: version }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    employee.reload
    expect(employee.onboarding_step).to eq('verified')
    expect(employee.consent_given_at).to be_present
    expect(employee.consent_text_version).to eq(version)
    expect(conversation.reload.status).to eq('profiling')
    expect(conversation.messages.where(direction: 'inbound')).to be_empty # consent is not an "answer"
    expect(conversation.messages.where(direction: 'outbound').pluck(:body).join(' ')).not_to match(/whatsapp/i)

    post '/api/v1/public/discover/consent', params: { version: version }, headers: headers, as: :json
    expect(response.parsed_body).to include('accepted' => true, 'already' => true)
  end

  it 'refuses a stale wording version and requires the employee session' do
    post '/api/v1/public/discover/consent', params: { version: 'web-avatar-000000000000' }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(employee.reload.onboarding_step).to eq('awaiting_consent')
    post '/api/v1/public/discover/consent', params: { version: 'x' }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
