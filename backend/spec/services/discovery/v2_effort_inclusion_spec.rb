require 'rails_helper'

RSpec.describe 'V2 effort inclusion contract' do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: 'hr', onboarding_step: 'verified') }
  let(:conversation) { create(:conversation, company: company, employee: employee, status: 'discovery') }
  let(:quote) { 'Scheduling interviews is included in recruitment coordination; no separate estimate.' }
  let(:source) { create(:message, conversation: conversation, direction: 'inbound', track: 'discovery', channel: 'web',
    body: "Recruitment coordination weekly, 4-6 hours per week. Scheduling interviews as needed, previously 1-2 hours. #{quote}") }

  def fact(text)
    { 'value' => text, 'quote' => text, 'source_message_id' => source.id, 'fact_status' => 'REPORTED',
      'correction' => false, 'evidence' => [{ 'message_id' => source.id, 'quote' => text }] }
  end

  def result
    parent = { 'id' => 'work-1', 'description' => fact('Recruitment coordination'), 'frequency' => fact('weekly'),
      'effort' => fact('4-6 hours per week').merge('minimum' => 4, 'maximum' => 6, 'unit' => 'hours', 'basis' => 'per_week'),
      'is_periodic' => false, 'systems_touched' => [], 'outputs' => [], 'handoffs' => [] }
    child = parent.deep_dup.merge('id' => 'work-2', 'description' => fact('Scheduling interviews'), 'frequency' => fact('as needed'),
      'effort' => fact('1-2 hours').merge('minimum' => 1, 'maximum' => 2, 'unit' => 'hours'),
      'effort_inclusion' => fact(quote).merge('value' => 'work-1'))
    checks = %w[anchor weekly monthly seasonal SLOWER_THAN_EXPECTED DUPLICATE_ENTRY CHASING_WAITING TRUST_CHECKING OUTSIDE_SYSTEMS shadow_ai]
    { 'completed' => false, 'question_count' => 4, 'assistant_message' => 'Please confirm the read-back.',
      'blackboard' => { 'employee_discovery_v2' => { 'version' => 2, 'revision' => 2, 'work_items' => [parent, child],
        'checks' => checks.to_h { |key| [key, fact('Recruitment coordination')] }, 'invisible_work_signals' => [], 'shadow_ai_signals' => [] } } }
  end

  def validate(value)
    Discovery::V2Contract.prepare!(value, conversation: conversation, source: source)
    value.dig('blackboard', 'employee_discovery_v2')
  end

  it 'keeps both activities, covers included effort and publishes only one additive range' do
    value = result
    data = validate(value)
    expect(data['coverage']['sizing']).to be(true)
    expect(data['work_items'].size).to eq(2)
    parent, child = data['canonical_work_items']
    expect(parent).to include('effort_range_min' => 4, 'effort_range_max' => 6, 'effort_counting' => 'SEPARATE_ESTIMATE')
    expect(child).to include('effort_range_min' => nil, 'effort_range_max' => nil, 'effort_unit' => nil,
      'effort_included_in_work_item_id' => "#{conversation.id}:work-1", 'effort_counting' => 'INCLUDED_IN_OTHER_WORK')
    expect(child['evidence_refs']).to be_present
    expect(data['work_items'].last.dig('effort', 'minimum')).to eq(1) # Historical estimate retained.
    conversation.update!(state_snapshot: { 'blackboard' => value['blackboard'] })
    sources = TaskSources::SyncFromConversation.call(conversation: conversation)
    child_source = sources.find { |s| s.name == 'Scheduling interviews' }
    expect(child_source.source_snapshot.dig('facts', 'effort')).to include('status' => 'unknown', 'minimum' => nil,
      'included_in_work_item_id' => "#{conversation.id}:work-1")
  end

  it 'still requires read-back confirmation before a successful grouped interview' do
    value = result
    data = validate(value)
    data['presented_summary'] = { 'text' => 'Recruitment: 4-6 hours weekly; interviews included.', 'revision' => data['revision'] }
    conversation.update!(state_snapshot: { 'blackboard' => value['blackboard'] })
    confirmation = create(:message, conversation: conversation, direction: 'inbound', track: 'discovery', body: 'Yes')
    data['confirmation'] = { 'revision' => data['revision'], 'summary_sha256' => Digest::SHA256.hexdigest(data['presented_summary']['text']),
      'evidence' => [{ 'message_id' => confirmation.id, 'quote' => 'Yes' }] }
    data['outcome'] = 'successful'
    value['completed'] = true
    expect { Discovery::V2Contract.prepare!(value, conversation: conversation, source: confirmation) }.not_to raise_error
  end

  it 'does not manufacture covered effort when the parent estimate is unknown' do
    value = result
    value.dig('blackboard', 'employee_discovery_v2', 'work_items').first['effort'] = fact('no separate estimate').merge(
      'value' => nil, 'fact_status' => 'UNKNOWN', 'minimum' => nil, 'maximum' => nil, 'unit' => nil)
    data = validate(value)
    # Approved policy: an evidenced, employee-stated unknown completes sizing (it is
    # an answer, with a follow-up), but no effort figure is ever manufactured.
    expect(data['coverage']['sizing']).to be(true)
    parent, *children = data['canonical_work_items']
    expect(parent).to include('effort_range_min' => nil, 'effort_range_max' => nil, 'effort_counting' => 'UNKNOWN')
    expect(children).to all(include('effort_range_min' => nil, 'effort_counting' => 'INCLUDED_IN_OTHER_WORK'))
  end

  it 'still blocks sizing coverage when an unknown estimate has no employee evidence' do
    value = result
    value.dig('blackboard', 'employee_discovery_v2', 'work_items').first.delete('effort') # never supplied
    expect(validate(value)['coverage']['sizing']).to be(false)
  end

  it 'does not count unresolved inclusion as separate additive effort' do
    value = result
    value.dig('blackboard', 'employee_discovery_v2', 'work_items').last['effort_inclusion']['fact_status'] = 'CONTRADICTED'
    data = validate(value)
    expect(data['coverage']['sizing']).to be(false)
    expect(data['canonical_work_items'].last).to include('effort_range_min' => nil, 'effort_counting' => 'UNRESOLVED_INCLUSION')
  end

  it 'rejects invented references and cyclic overlap without changing the conversation' do
    ['work-2', 'work-999'].each do |parent_id|
      value = result
      value.dig('blackboard', 'employee_discovery_v2', 'work_items').last['effort_inclusion']['value'] = parent_id
      expect { validate(value) }.to raise_error(Langgraph::UnavailableError)
    end
    value = result
    value.dig('blackboard', 'employee_discovery_v2', 'work_items').first['effort_inclusion'] = fact(quote).merge('value' => 'work-2')
    expect { validate(value) }.to raise_error(Langgraph::UnavailableError, 'Invalid or cyclic effort inclusion')
    expect(conversation.reload.state_snapshot).to eq({})
  end

  it 'rejects topic similarity or a negated overlap as inclusion evidence' do
    ['I also handle recruitment coordination', 'Scheduling interviews is not included in recruitment coordination'].each do |text|
      source.update!(body: "#{source.body} #{text}")
      value = result
      value.dig('blackboard', 'employee_discovery_v2', 'work_items').last['effort_inclusion'] = fact(text).merge('value' => 'work-1')
      expect { validate(value) }.to raise_error(Langgraph::UnavailableError, 'Unsupported effort inclusion')
    end
  end

  it 'accepts a short yes only when it answers the real preceding scope question for both activities' do
    value = result
    data = value.dig('blackboard', 'employee_discovery_v2')
    question = create(:message, conversation: conversation, direction: 'outbound', track: 'discovery',
      body: 'Is all the effort for Scheduling interviews already included in your estimate for Recruitment coordination?')
    answer = create(:message, conversation: conversation, direction: 'inbound', track: 'discovery', body: 'Yes')
    link = { 'value' => 'work-1', 'fact_status' => 'REPORTED', 'quote' => 'Yes', 'source_message_id' => answer.id,
      'scope_question' => question.body, 'evidence' => [{ 'message_id' => answer.id, 'quote' => 'Yes' }] }
    data['work_items'].last['effort_inclusion'] = link
    expect { Discovery::V2Contract.prepare!(value, conversation: conversation, source: answer) }.not_to raise_error
    expect(data['coverage']['sizing']).to be(true)
    description = data['work_items'].last['description']
    description['history'] = [description.deep_dup]
    description['value'] = 'Arranging candidate interviews'
    expect { Discovery::V2Contract.prepare!(value, conversation: conversation, source: answer) }.not_to raise_error
    link['scope_question'] = 'An invented interviewer question'
    expect { Discovery::V2Contract.prepare!(value, conversation: conversation, source: answer) }
      .to raise_error(Langgraph::UnavailableError, 'Unsupported effort inclusion')
  end
end
