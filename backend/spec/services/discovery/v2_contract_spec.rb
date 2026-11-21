require 'rails_helper'

RSpec.describe Discovery::V2Contract do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: 'finance', onboarding_step: 'verified') }
  let(:conversation) { create(:conversation, company: company, employee: employee, status: 'discovery', question_count: 0) }
  let(:source) { create(:message, conversation: conversation, direction: 'inbound', channel: 'web', track: 'discovery', body: 'Review invoices daily for 20 to 30 minutes') }

  def fact(value)
    { 'value' => value, 'quote' => value, 'source_message_id' => source.id, 'fact_status' => 'REPORTED',
      'correction' => false, 'evidence' => [{ 'message_id' => source.id, 'quote' => value }] }
  end

  def result
    item = { 'id' => 'work-1', 'description' => fact('Review invoices'), 'frequency' => fact('daily'),
      'effort' => fact('20 to 30 minutes').merge('minimum' => 20, 'maximum' => 30, 'unit' => 'minutes'),
      'is_periodic' => false, 'systems_touched' => [], 'outputs' => [], 'handoffs' => [] }
    { 'question_count' => 1, 'assistant_message' => 'What other weekly work is missing?', 'completed' => false,
      'blackboard' => { 'employee_discovery_v2' => { 'version' => 2, 'revision' => 1, 'prompt_version' => 'employee-discovery-v2.1',
        'work_items' => [item], 'checks' => { 'anchor' => fact('Review invoices') }, 'invisible_work_signals' => [], 'shadow_ai_signals' => [] } } }
  end

  it 'creates tenant-scoped canonical objects with evidence, fact statuses and ranges' do
    value = result
    described_class.prepare!(value, conversation: conversation, source: source)
    data = value.dig('blackboard', 'employee_discovery_v2')
    work = data['canonical_work_items'].first
    expect(work).to include('company_id' => company.id, 'effort_range_min' => 20, 'effort_range_max' => 30,
      'fact_status' => 'REPORTED', 'benefit_state' => 'DISCOVERY_ESTIMATE', 'role_profile_id' => data['role_profile']['id'])
    expect(work['evidence_refs']).not_to be_empty
    expect(data['evidence_references'].first).to include('source_id' => source.id, 'actor_id' => employee.id,
      'source_type' => 'CHAT_MESSAGE', 'sensitivity' => 'CONFIDENTIAL', 'retention_status' => 'ACTIVE')
    expect(data['coverage']['sizing']).to be(true)
  end

  it 'uses transcript turn references for spoken answers' do
    source.update!(message_type: 'audio')
    value = result
    described_class.prepare!(value, conversation: conversation, source: source)
    expect(value.dig('blackboard', 'employee_discovery_v2', 'evidence_references').map { |e| e['source_type'] }.uniq).to eq(['TRANSCRIPT'])
  end

  it 'records live avatar answers (typed path, spoken input) as transcripts' do
    source.update!(raw_payload: { 'input_mode' => 'voice', 'interrupted_question' => false })
    value = result
    described_class.prepare!(value, conversation: conversation, source: source)
    expect(value.dig('blackboard', 'employee_discovery_v2', 'evidence_references').map { |e| e['source_type'] }.uniq).to eq(['TRANSCRIPT'])
  end

  it 'preserves a reported weekly effort total without turning it into per-interview time' do
    source.update!(body: 'Recruitment coordination takes 4–6 hours per week.')
    value = result
    item = value.dig('blackboard', 'employee_discovery_v2', 'work_items').first
    item['description'] = fact('Recruitment coordination')
    item['frequency'] = fact('per week')
    item['effort'] = fact('4–6 hours per week').merge('minimum' => 4, 'maximum' => 6, 'unit' => 'hours', 'basis' => 'per_week')
    value.dig('blackboard', 'employee_discovery_v2')['checks'] = { 'anchor' => fact('Recruitment coordination') }
    described_class.prepare!(value, conversation: conversation, source: source)
    canonical = value.dig('blackboard', 'employee_discovery_v2', 'canonical_work_items').first
    expect(canonical).to include('effort_range_min' => 4, 'effort_range_max' => 6, 'effort_unit' => 'hours', 'effort_basis' => 'per_week')
    expect(canonical['evidence_refs']).to be_present
  end

  it 'rejects another participant source even inside the same company' do
    other = create(:conversation, company: company, employee: create(:employee, company: company))
    message = create(:message, conversation: other, direction: 'inbound', track: 'discovery', body: source.body)
    value = result
    value.dig('blackboard', 'employee_discovery_v2', 'work_items').first['description']['evidence'].first['message_id'] = message.id
    expect { described_class.prepare!(value, conversation: conversation, source: source) }.to raise_error(Langgraph::UnavailableError, 'Cross-context or fabricated evidence')
  end

  it 'rejects completion without a previously presented employee summary' do
    value = result.merge('completed' => true)
    value.dig('blackboard', 'employee_discovery_v2')['outcome'] = 'successful'
    expect { described_class.prepare!(value, conversation: conversation, source: source) }.to raise_error(Langgraph::UnavailableError, 'Unconfirmed discovery completion')
  end

  it 'does not accept measured or consultant-confirmed discovery estimates' do
    value = result
    value.dig('blackboard', 'employee_discovery_v2', 'work_items').first['effort']['fact_status'] = 'OBSERVED'
    expect { described_class.prepare!(value, conversation: conversation, source: source) }.to raise_error(Langgraph::UnavailableError)
  end

  it 'projects canonical activities to the existing task source pipeline without inventing process detail' do
    value = result
    described_class.prepare!(value, conversation: conversation, source: source)
    conversation.update!(state_snapshot: { 'blackboard' => value['blackboard'] })
    sources = TaskSources::SyncFromConversation.call(conversation: conversation)
    expect(sources.size).to eq(1)
    expect(sources.first.name).to eq('Review invoices')
    expect(sources.first.source_snapshot['work_item']['effort_range_min']).to eq(20)
    expect(sources.first.source_snapshot['facts']).not_to have_key('steps_decisions')
  end

  it 'uses V2 for new interviews and keeps existing workflow interviews on their engine' do
    expect(Discovery::EmployeeContext.v2?(conversation)).to be(true)
    conversation.update!(question_count: 2)
    expect(Discovery::EmployeeContext.v2?(conversation)).to be(false)
    conversation.update!(question_count: 0, state_snapshot: { 'blackboard' => { 'dossier' => { 'workflow' => {} } } })
    expect(Discovery::EmployeeContext.v2?(conversation)).to be(false)
  end

  it 'versions an explicit activity withdrawal and retires its task source without erasing earlier work' do
    value = result
    described_class.prepare!(value, conversation: conversation, source: source)
    conversation.update!(state_snapshot: { 'blackboard' => value['blackboard'] })
    TaskSources::SyncFromConversation.call(conversation: conversation)
    correction = create(:message, conversation: conversation, direction: 'inbound', track: 'discovery', body: 'Actually I do not review invoices')
    data = conversation.blackboard['employee_discovery_v2'].deep_dup
    withdrawn = data['work_items'].shift
    withdrawn['retirement'] = { 'value' => correction.body, 'fact_status' => 'REPORTED',
      'quote' => correction.body, 'source_message_id' => correction.id,
      'evidence' => [{ 'message_id' => correction.id, 'quote' => correction.body }] }
    data['retired_work_items'] = [withdrawn]
    data['revision'] += 1
    updated = { 'completed' => false, 'blackboard' => { 'employee_discovery_v2' => data } }
    described_class.prepare!(updated, conversation: conversation, source: correction)
    conversation.update!(state_snapshot: { 'blackboard' => updated['blackboard'] })
    expect(TaskSources::SyncFromConversation.call(conversation: conversation)).to be_empty
    expect(conversation.task_sources.where(local_task_id: 'work-1').order(version: :desc).first).to be_retired
    expect(data['canonical_retired_work_items'].first['retired']).to be(true)
    expect(data['retired_work_items'].first.dig('description', 'value')).to eq('Review invoices')
  end

  it 'does not retrieve peer facts, company documents, knowledge or management context for V2' do
    expect(company).not_to receive(:company_memory_facts)
    expect(company).not_to receive(:company_knowledge_entries)
    context = Discovery::ContextBuilder.call(conversation: conversation, employee: employee, user_message: 'Invoices')
    expect(context).to include(memory_facts: [], document_snippets: [], knowledge_snippets: [], media_snippets: [])
    expect(context[:company_profile].keys - Discovery::EmployeeContext::BASICS).to be_empty
  end

  it 'redacts explicit credentials before model context assembly' do
    text = 'Outlook password=do-not-send api_key=another-secret'
    expect(Discovery::EmployeeContext.redact(text)).to eq('Outlook [REDACTED] [REDACTED]')
  end

  it 'recognizes reported spoken numbers without converting units or inventing precision' do
    expect(Discovery::EmployeeContext.evidence_numbers('twenty five to thirty minutes')).to include(25, 30)
    expect(Discovery::EmployeeContext.evidence_numbers('half an hour to an hour')).to include(0.5, 1)
    expect(Discovery::EmployeeContext.evidence_numbers('خمس إلى عشر دقائق')).to include(5, 10)
    expect(Discovery::EmployeeContext.evidence_numbers('٥ إلى ١٠ دقائق')).to include(5, 10)
  end

  it 'preserves the original saved answer and durable recovery when a V2 response is invalid' do
    create(:discovery_playbook, department: 'finance')
    conversation.update!(langgraph_thread_id: SecureRandom.uuid)
    client = instance_double(Langgraph::Client)
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow(client).to receive(:run_turn!).and_return('assistant_message' => 'Invented completion', 'completed' => true)
    output = Discovery::ProcessTurnService.call(conversation: conversation, employee: employee, user_message: source.body, inbound_message: source)
    expect(output['error_code']).to eq('invalid_discovery_v2_contract')
    expect(source.reload.body).to eq('Review invoices daily for 20 to 30 minutes')
    expect(DiscoveryTurn.find_by!(source_message: source).status).to eq('failed')
    expect(conversation.reload.status).to eq('discovery')
  end
end
