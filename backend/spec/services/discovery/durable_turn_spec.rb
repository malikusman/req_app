require 'rails_helper'

RSpec.describe 'Durable discovery processing' do
  include ActiveSupport::Testing::TimeHelpers
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: 'hr') }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: 'discovery', question_count: 0, langgraph_thread_id: SecureRandom.uuid) }
  let(:source) { create(:message, conversation: conversation, direction: 'inbound', channel: 'web', body: 'I coordinate recruitment') }
  let(:client) { instance_double(Langgraph::Client) }
  let(:reply) { { 'assistant_message' => 'Next question?', 'question_count' => 1, 'completed' => false } }

  before do
    create(:discovery_playbook, department: 'hr')
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  def process
    Discovery::ProcessTurnService.call(conversation: conversation, employee: employee, user_message: source.body, inbound_message: source)
  end

  it 'rejects a late result without applying any state' do
    allow(client).to receive(:run_turn!) do
      travel_to(100.seconds.from_now)
      reply
    end
    begin
      expect(process['delayed']).to be(true)
      expect(conversation.reload.question_count).to eq(0)
      expect(source.reload.body).to eq('I coordinate recruitment')
      expect(DiscoveryTurn.find_by!(source_message: source).status).to eq('retry_waiting')
      expect(conversation.messages.where(direction: 'outbound')).to be_empty
    ensure
      travel_back
    end
  end

  it 'enforces the deadline even when an optional processing layer rescues StandardError' do
    stub_const('Discovery::DurableTurn::BUDGET', 0.05)
    allow(client).to receive(:run_turn!) do
      begin
        sleep 1
      rescue StandardError
        retry
      end
      reply
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(process['error_code']).to eq('deadline_exceeded')
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.8
    expect(conversation.reload.question_count).to eq(0)
    expect(source.reload.body).to eq('I coordinate recruitment')
  end

  it 'fences a result when the conversation state changed during its request' do
    allow(client).to receive(:run_turn!) do
      Conversation.find(conversation.id).update!(state_snapshot: { 'newer_state' => true }, discovery_revision: 2)
      reply
    end
    expect(process['error_code']).to eq('stale_turn')
    expect(conversation.reload.state_snapshot).to eq('newer_state' => true)
    expect(conversation.question_count).to eq(0)
    expect(source.reload.raw_payload).not_to have_key('discovery_result')
  end

  it 'fences a replaced processing lease' do
    allow(client).to receive(:run_turn!) do
      DiscoveryTurn.find_by!(source_message: source).update!(lease_token: 'new-owner')
      reply
    end
    process
    expect(conversation.reload.question_count).to eq(0)
    expect(source.reload.raw_payload).not_to have_key('discovery_result')
  end

  it 'recovers queued intent after enqueue failure or Sidekiq restart' do
    turn = Discovery::DurableTurn.register(conversation, source, source.body)
    allow(ProcessDiscoveryTurnJob).to receive(:perform_later).and_raise('Redis unavailable')
    expect { turn.enqueue_processing }.not_to raise_error
    expect(turn.reload.status).to eq('queued')
    allow(ProcessDiscoveryTurnJob).to receive(:perform_later)
    RecoverDiscoveryTurnsJob.perform_now
    expect(ProcessDiscoveryTurnJob).to have_received(:perform_later).with(turn.id).at_least(:once)
    allow(client).to receive(:run_turn!).and_return(reply)
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    expect(conversation.reload.question_count).to eq(1)
    expect(source.reload.raw_payload['discovery_result']).to be_present
  end

  it 'recovers an expired processing lease without losing its source identity' do
    turn = Discovery::DurableTurn.register(conversation, source, source.body)
    turn.update!(status: 'processing', lease_token: 'dead-worker', lease_until: 1.second.ago)
    allow(client).to receive(:run_turn!).and_return(reply)
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    expect(conversation.reload.question_count).to eq(1)
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'atomically commits the result and web reply and survives duplicate recovery' do
    expect(client).to receive(:run_turn!).once.and_return(reply)
    process
    turn = DiscoveryTurn.find_by!(source_message: source)
    expect(turn.status).to eq('succeeded')
    expect(source.reload.raw_payload['discovery_result']).to be_present
    2.times { RecoverDiscoveryTurnsJob.perform_now }
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'resumes an old successful result whose reply was never persisted' do
    identified = reply.merge('source_message_id' => source.id)
    turn = Discovery::DurableTurn.register(conversation, source, source.body)
    turn.update!(status: 'succeeded', result: identified)
    expect(client).not_to receive(:run_turn!)
    2.times { RecoverDiscoveryTurnsJob.perform_now }
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'adopts a legacy successful result without its source tag and delivers it only once' do
    source.update!(raw_payload: { 'discovery_result' => reply })
    expect(client).not_to receive(:run_turn!)
    2.times { RecoverDiscoveryTurnsJob.perform_now }
    turn = DiscoveryTurn.find_by!(source_message: source)
    expect(turn.result['source_message_id']).to eq(source.id)
    expect(turn.reply_message_id).to be_present
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'does not process a later answer while an earlier failed answer is unresolved' do
    earlier = Discovery::DurableTurn.register(conversation, source, source.body)
    earlier.update!(status: 'failed', error_code: 'openai_quota_exceeded')
    later = create(:message, conversation: conversation, direction: 'inbound', channel: 'web', body: 'Another answer')
    expect(client).not_to receive(:run_turn!)
    result = Discovery::ProcessTurnService.call(conversation: conversation, employee: employee, user_message: later.body, inbound_message: later)
    expect(result['delayed']).to be(true)
    expect(conversation.reload.question_count).to eq(0)
  end

  it 'does not include later queued WhatsApp answers in the earlier source history' do
    source
    later = create(:message, conversation: conversation, direction: 'inbound', channel: 'whatsapp', body: 'Later queued answer')
    expect(client).to receive(:run_turn!) do |payload|
      expect(payload[:history].map { |item| item[:message_id] }).to include(source.id)
      expect(payload[:history].map { |item| item[:message_id] }).not_to include(later.id)
      reply
    end
    process
  end
  it 'rolls back AI success if reply persistence crashes and recovers from the durable lease' do
    allow(client).to receive(:run_turn!).and_return(reply)
    allow(Discovery::DeliverReply).to receive(:call).and_raise('crash before reply commit')
    expect { process }.to raise_error('crash before reply commit')
    turn = DiscoveryTurn.find_by!(source_message: source)
    expect(conversation.reload.question_count).to eq(0)
    expect(source.reload.body).to eq('I coordinate recruitment')
    expect(source.raw_payload).not_to have_key('discovery_result')
    turn.update!(lease_until: 1.second.ago)
    allow(Discovery::DeliverReply).to receive(:call).and_call_original
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    expect(conversation.reload.question_count).to eq(1)
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'monotonically fences state updates made by existing services outside the turn processor' do
    original = conversation.discovery_revision
    Conversation.where(id: conversation.id).update_all(state_snapshot: { 'existing_service_change' => true })
    expect(conversation.reload.discovery_revision).to be > original
  end

  it 'resumes committed WhatsApp delivery intent once without another model call' do
    source.update!(channel: 'whatsapp')
    allow(client).to receive(:run_turn!).and_return(reply)
    process
    outbound = conversation.messages.find_by!(reply_to_message_id: source.id)
    expect(outbound.delivery_status).to eq('pending')
    meta = instance_double(Whatsapp::MetaClient, configured?: true)
    allow(Whatsapp::MetaClient).to receive(:new).and_return(meta)
    expect(meta).to receive(:send_text).once.with(to: employee.phone_e164, body: 'Next question?')
    2.times { DeliverDiscoveryReplyJob.perform_now(outbound.id) }
    expect(outbound.reload.delivery_status).to eq('sent')
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'does not resend an ambiguous provider delivery after a worker crash' do
    outbound = create(:message, conversation: conversation, direction: 'outbound', body: 'Persisted reply',
      delivery_status: 'processing', delivery_lease_until: 1.second.ago)
    RecoverDiscoveryTurnsJob.perform_now
    expect(outbound.reload.delivery_status).to eq('uncertain')
    expect(Whatsapp::MetaClient).not_to receive(:new)
    DeliverDiscoveryReplyJob.perform_now(outbound.id)
  end

  it 'deduplicates WhatsApp webhook replays and atomically records recovery intent' do
    employee.update!(onboarding_step: 'verified', participation_status: 'started')
    conversation # Ensure the existing discovery thread is selected.
    payload = { 'entry' => [{ 'changes' => [{ 'value' => { 'messages' => [
      { 'id' => 'durable-webhook-test', 'from' => employee.phone_e164.delete_prefix('+'),
        'type' => 'text', 'text' => { 'body' => 'WhatsApp saved answer' } }
    ] } }] }] }
    expect(client).not_to receive(:run_turn!)
    2.times { Whatsapp::InboundProcessor.new(payload).process }
    messages = conversation.messages.where(external_id: 'durable-webhook-test')
    expect(messages.count).to eq(1)
    expect(DiscoveryTurn.where(source_message: messages.first).count).to eq(1)
    expect(WebhookEvent.find_by!(external_id: 'durable-webhook-test').status).to eq('processed')
  end

  it 'recovers an extracted attachment after a crash before discovery dispatch' do
    source.update!(message_type: 'audio', processing_status: 'ready', raw_payload: { 'discovery_media_pending' => true })
    media = create(:media_attachment, message: source, status: 'ready', extracted_text: source.body, updated_at: 2.minutes.ago)
    expect { RecoverDiscoveryTurnsJob.perform_now }.to have_enqueued_job(ContinueDiscoveryAfterMediaJob).with(media.id)
    2.times { ContinueDiscoveryAfterMediaJob.perform_now(media.id) }
    turn = DiscoveryTurn.find_by!(source_message: source)
    expect(turn.user_message).to eq(source.body)
    expect(source.reload.raw_payload).not_to have_key('discovery_media_pending')
    expect(client).to receive(:run_turn!).once.and_return(reply)
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    expect(conversation.reload.question_count).to eq(1)
    expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
  end

  it 'releases the media processing ownership when extraction raises' do
    media = create(:media_attachment, message: source)
    allow(Multimodal::ProcessMediaService).to receive(:call).and_raise('extraction worker failed')
    expect { ProcessMediaAttachmentJob.perform_now(media.id) }.to raise_error('extraction worker failed')
    locks = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()")
    expect(locks.to_i).to eq(0)
  end

end
