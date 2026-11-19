require 'rails_helper'

RSpec.describe 'Saved recruitment estimate recovery', type: :request do
  it 'reuses one saved submission, turn and reply across manual retry and duplicate jobs' do
    company = create(:company)
    employee = create(:employee, company: company, department: 'hr', onboarding_step: 'verified', participation_status: 'started')
    conversation = create(:conversation, employee: employee, company: company, status: 'discovery',
      question_count: 14, langgraph_thread_id: SecureRandom.uuid,
      state_snapshot: { 'discovery_engine_version' => 2, 'blackboard' => { 'employee_discovery_v2' => {
        'version' => 2, 'revision' => 2, 'work_items' => [], 'checks' => {}, 'invisible_work_signals' => [], 'shadow_ai_signals' => [] } } })
    session = create(:employee_web_session, employee: employee, company: company, verified_at: Time.current)
    headers = employee_web_headers(session: session, employee: employee)
    create(:discovery_playbook, department: 'hr')
    submission = EmployeeSubmission.create!(conversation: conversation, submission_id: SecureRandom.uuid,
      body: 'Recruitment coordination takes 4–6 hours per week.')
    source = create(:message, conversation: conversation, employee_submission: submission, direction: 'inbound', channel: 'web',
      track: 'discovery', body: submission.body, raw_payload: { 'discovery_pending' => false, 'discovery_error' => 'discovery_clarification_required' })
    turn = Discovery::DurableTurn.register(conversation, source, source.body)
    expect(turn.status).to eq('failed')
    original_identity = turn.identity
    evidence = ->(quote) { { 'value' => quote, 'quote' => quote, 'source_message_id' => source.id, 'fact_status' => 'REPORTED',
      'correction' => false, 'evidence' => [{ 'message_id' => source.id, 'quote' => quote }] } }
    item = { 'id' => 'work-11', 'description' => evidence.call('Recruitment coordination'), 'frequency' => evidence.call('per week'),
      'effort' => evidence.call('4–6 hours per week').merge('minimum' => 4, 'maximum' => 6, 'unit' => 'hours', 'basis' => 'per_week'),
      'systems_touched' => [], 'outputs' => [], 'handoffs' => [], 'is_periodic' => false }
    result = { 'completed' => false, 'assistant_message' => 'How long does reviewing attendance records usually take?', 'question_count' => 15,
      'blackboard' => { 'employee_discovery_v2' => { 'version' => 2, 'revision' => 3, 'prompt_version' => 'employee-discovery-v2.1',
        'work_items' => [item], 'checks' => {}, 'invisible_work_signals' => [], 'shadow_ai_signals' => [] } } }
    client = instance_double(Langgraph::Client)
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    expect(client).to receive(:run_turn!).once.with(hash_including(user_message: source.body)).and_return(result)

    get '/api/v1/public/discover/messages', headers: headers
    expect(response.parsed_body['state']).to include('discovery_pending' => false, 'discovery_error' => 'discovery_clarification_required')
    post '/api/v1/public/discover/messages', params: { retry: true }, headers: headers
    expect(response).to have_http_status(:ok)
    post '/api/v1/public/discover/messages', params: { retry: true }, headers: headers
    expect(response).to have_http_status(:conflict)
    2.times { ProcessDiscoveryTurnJob.perform_now(turn.id) }
    expect(turn.reload.status).to eq('succeeded')
    expect(turn.identity).to eq(original_identity)
    expect(turn.source_message_id).to eq(source.id)
    expect(conversation.messages.where(direction: 'inbound').count).to eq(1)
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
    expect(conversation.discovery_turns.count).to eq(1)
    expect(source.reload.body).to eq(submission.body)
    expect(source.employee_submission_id).to eq(submission.id)
    expect(conversation.reload.question_count).to eq(15)
    expect(conversation.blackboard.dig('employee_discovery_v2', 'canonical_work_items').first['effort_basis']).to eq('per_week')
    get '/api/v1/public/discover/messages', headers: headers
    expect(response.parsed_body['state']).to include('discovery_pending' => false, 'discovery_error' => nil)

    # Repair of an already committed response preserves identity and an audit
    # version instead of defeating idempotency by re-admitting the saved answer.
    original_reply = turn.reply_message
    original_body = original_reply.body
    revision = conversation.reload.discovery_revision
    corrected = result.deep_dup.merge('assistant_message' => 'For reviewing attendance records, what is your approximate active effort?')
    arguments = { turn_id: turn.id, result: corrected, expected_revision: revision,
      expected_source_sha256: Digest::SHA256.hexdigest(source.body), correction_id: 'recruitment-attribution-test',
      playbook: DiscoveryPlaybook.active_playbook_for('hr') }
    2.times { Discovery::CorrectSavedV2Result.call(**arguments) }
    expect(turn.reload.reply_message_id).to eq(original_reply.id)
    expect(original_reply.reload.body).to eq(corrected['assistant_message'])
    expect(source.reload.raw_payload['discovery_result_corrections'].size).to eq(1)
    expect(source.raw_payload['discovery_result_corrections'].first['previous_reply_body']).to eq(original_body)
    expect(conversation.reload.question_count).to eq(15)
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
    expect { Discovery::CorrectSavedV2Result.call(**arguments.merge(correction_id: 'stale-revision')) }
      .to raise_error(Discovery::CorrectSavedV2Result::Conflict, 'Conversation changed during correction')
    create(:message, conversation: conversation, direction: 'inbound', channel: 'web', body: 'A later answer')
    expect { Discovery::CorrectSavedV2Result.call(**arguments.merge(correction_id: 'newer-answer', expected_revision: conversation.reload.discovery_revision)) }
      .to raise_error(Discovery::CorrectSavedV2Result::Conflict, 'Only the latest committed web reply can be corrected')
  end
end
