# frozen_string_literal: true

require 'rails_helper'

# B2 regression: a saved answer the V2 engine could not process must not strand the
# employee behind a Retry button that replays identical input. A rephrased answer
# supersedes it; the original message, error and failed turn remain on record.
RSpec.describe 'Employee Discovery V2 rephrase after a failed answer', type: :request do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, onboarding_step: 'verified', participation_status: 'started', department: 'hr', role_title: 'HR Officer') }
  let!(:session) { create(:employee_web_session, employee: employee, company: company, verified_at: Time.current) }
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) do
    create(:conversation, employee: employee, company: company, status: 'discovery', question_count: 1, langgraph_thread_id: SecureRandom.uuid,
      state_snapshot: { 'discovery_engine_version' => 2, 'blackboard' => { 'employee_discovery_v2' => {
        'version' => 2, 'revision' => 0, 'work_items' => [], 'checks' => {}, 'phase' => 'anchor', 'last_check' => 'anchor',
        'last_question' => 'Thinking of your last working day, could you walk me through what you actually did?' } } })
  end
  let!(:question) { create(:message, conversation: conversation, direction: 'outbound', track: 'discovery', body: 'Thinking of your last working day…') }

  def failed_answer(code)
    source = create(:message, conversation: conversation, direction: 'inbound', track: 'discovery', body: 'It took about an hour.',
      raw_payload: { 'discovery_pending' => false, 'discovery_error' => code })
    [source, Discovery::DurableTurn.register(conversation, source, source.body)]
  end

  before do
    create(:discovery_playbook, department: 'hr')
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow_any_instance_of(DiscoveryTurn).to receive(:enqueue_processing)
  end

  it 'lets the employee rephrase an unprocessable answer and keeps the original on record' do
    source, turn = failed_answer('invalid_discovery_evidence')
    expect(turn.status).to eq('failed')
    get '/api/v1/public/discover/messages', headers: headers
    expect(response.parsed_body['state']).to include('discovery_phase' => 'failed', 'can_rephrase' => true)

    post '/api/v1/public/discover/messages', params: { body: 'I spent around one hour on the HR inbox.', submission_id: SecureRandom.uuid }, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(turn.reload.status).to eq('superseded')
    expect(turn.error_code).to eq('invalid_discovery_evidence')
    expect(source.reload.body).to eq('It took about an hour.')
    expect(source.raw_payload).to include('discovery_superseded' => include('error_code' => 'invalid_discovery_evidence'))
    expect(source.raw_payload).not_to have_key('discovery_error')
    replacement = DiscoveryTurn.where(conversation: conversation).where.not(id: turn.id).sole
    expect(replacement.source_message.body).to eq('I spent around one hour on the HR inbox.')
    expect(response.parsed_body['state']['can_rephrase']).to be(false)
    # A superseded turn is terminal: it is never processed or recovered again.
    expect(DiscoveryTurn.unresolved.where(id: turn.id)).to be_empty
    expect(Discovery::DurableTurn.call(Discovery::ProcessTurnService.allocate, turn)).to be_present
    expect(turn.reload.status).to eq('superseded')
  end

  it 'keeps transient failures on the retry-only path' do
    _, turn = failed_answer('openai_unavailable')
    get '/api/v1/public/discover/messages', headers: headers
    expect(response.parsed_body['state']['can_rephrase']).to be(false)
    post '/api/v1/public/discover/messages', params: { body: 'Another answer', submission_id: SecureRandom.uuid }, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(turn.reload.status).to eq('failed')
  end

  it 'does not supersede answers for interviews on the legacy engine' do
    conversation.update!(state_snapshot: { 'discovery_engine_version' => 1 })
    _, turn = failed_answer('invalid_discovery_evidence')
    post '/api/v1/public/discover/messages', params: { body: 'Another answer', submission_id: SecureRandom.uuid }, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(turn.reload.status).to eq('failed')
  end
end
