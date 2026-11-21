require 'rails_helper'

RSpec.describe 'Saved V2 attendance effort recovery', type: :request do
  it 'recovers the original short answer once while preserving other activities and prior evidence' do
    company = create(:company)
    employee = create(:employee, company: company, department: 'hr', onboarding_step: 'verified', participation_status: 'started')
    conversation = create(:conversation, employee: employee, company: company, status: 'discovery', question_count: 15,
      langgraph_thread_id: SecureRandom.uuid)
    session = create(:employee_web_session, employee: employee, company: company, verified_at: Time.current)
    headers = employee_web_headers(session: session, employee: employee)
    create(:discovery_playbook, department: 'hr')
    prior = create(:message, conversation: conversation, direction: 'inbound', channel: 'web', track: 'discovery',
      body: 'Reviewing attendance records daily. Recruitment coordination weekly, 4-6 hours per week.')
    fact = ->(text, source) { { 'value' => text, 'quote' => text, 'source_message_id' => source.id,
      'fact_status' => 'REPORTED', 'correction' => false, 'evidence' => [{ 'message_id' => source.id, 'quote' => text }] } }
    attendance = { 'id' => 'work-2', 'description' => fact.call('Reviewing attendance records', prior),
      'frequency' => fact.call('daily', prior), 'is_periodic' => false, 'systems_touched' => [], 'outputs' => [], 'handoffs' => [] }
    recruitment = attendance.deep_dup.merge('id' => 'work-11', 'description' => fact.call('Recruitment coordination', prior),
      'frequency' => fact.call('weekly', prior), 'effort' => fact.call('4-6 hours per week', prior).merge(
        'minimum' => 4, 'maximum' => 6, 'unit' => 'hours', 'basis' => 'per_week'))
    data = { 'version' => 2, 'revision' => 5, 'work_items' => [attendance, recruitment], 'checks' => {},
      'invisible_work_signals' => [], 'shadow_ai_signals' => [], 'phase' => 'size_close', 'last_item' => 'work-2' }
    Discovery::V2Contract.prepare!({ 'blackboard' => { 'employee_discovery_v2' => data }, 'completed' => false },
      conversation: conversation, source: prior)
    conversation.update!(state_snapshot: { 'discovery_engine_version' => 2, 'blackboard' => { 'employee_discovery_v2' => data } })
    submission = EmployeeSubmission.create!(conversation: conversation, submission_id: SecureRandom.uuid, body: '2 3 hrs')
    source = create(:message, conversation: conversation, employee_submission: submission, direction: 'inbound', channel: 'web',
      track: 'discovery', body: submission.body, raw_payload: { 'discovery_pending' => false, 'discovery_error' => 'invalid_discovery_evidence' })
    turn = Discovery::DurableTurn.register(conversation, source, source.body)
    identity = turn.identity
    recovered = data.deep_dup
    recovered['revision'] += 1
    recovered['work_items'][0]['effort'] = fact.call(source.body, source).merge('minimum' => 2, 'maximum' => 3, 'unit' => 'hours', 'basis' => nil)
    result = { 'completed' => false, 'question_count' => 16, 'assistant_message' => 'What is missing from this summary?',
      'blackboard' => { 'employee_discovery_v2' => recovered } }
    client = instance_double(Langgraph::Client)
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    expect(client).to receive(:run_turn!).once.with(hash_including(user_message: '2 3 hrs')).and_return(result)
    post '/api/v1/public/discover/messages', params: { retry: true }, headers: headers
    expect(response).to have_http_status(:ok)
    2.times { ProcessDiscoveryTurnJob.perform_now(turn.id) }
    expect(turn.reload.status).to eq('succeeded')
    expect(turn.identity).to eq(identity)
    expect(source.reload.body).to eq('2 3 hrs')
    expect(EmployeeSubmission.where(conversation: conversation).count).to eq(1)
    expect(DiscoveryTurn.where(source_message: source).count).to eq(1)
    expect(Message.where(reply_to_message_id: source.id).count).to eq(1)
    saved = conversation.reload.blackboard['employee_discovery_v2']
    expect(saved['work_items'][0]['description']).to eq(attendance['description'])
    expect(saved['work_items'][1]).to eq(recruitment)
    expect(saved['canonical_work_items'].first).to include('effort_range_min' => 2, 'effort_range_max' => 3, 'effort_unit' => 'hours')
    expect(conversation.question_count).to eq(16)
    get '/api/v1/public/discover/messages', headers: headers
    expect(response.parsed_body['state']).to include('discovery_phase' => 'idle', 'discovery_pending' => false, 'discovery_error' => nil)
  end
end
