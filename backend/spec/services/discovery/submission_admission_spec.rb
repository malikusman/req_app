require 'rails_helper'

RSpec.describe 'Atomic employee submission admission' do
  self.use_transactional_tests = false

  before do
    @company = create(:company)
    @employee = create(:employee, company: @company, department: 'hr')
    @conversation = create(:conversation, employee: @employee, company: @company, status: 'discovery', langgraph_thread_id: SecureRandom.uuid)
    ActiveRecord::Base.shared_connection = nil
  end

  after do
    DiscoveryTurn.where(conversation_id: @conversation.id).delete_all
    Message.where(conversation_id: @conversation.id).delete_all
    EmployeeSubmission.where(conversation_id: @conversation.id).delete_all
    if @playbook
      owner = @playbook.created_by_platform_user
      @playbook.destroy!
      owner.destroy!
    end
    @company.destroy!
  end

  def race(ids)
    barrier = Queue.new
    threads = ids.map do |key|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          begin
            Discovery::AdmitSubmission.call(conversation: Conversation.find(@conversation.id), employee: Employee.find(@employee.id), submission_id: key, body: 'Recruitment answer')
            :accepted
          rescue Discovery::AdmitSubmission::Conflict
            :conflict
          end
        end
      end
    end
    ids.length.times { barrier << true }
    threads.map(&:value)
  end

  it 'deduplicates simultaneous POST retries using real database connections' do
    expect(race(['same-id', 'same-id'])).to eq([:accepted, :accepted])
    expect(EmployeeSubmission.where(conversation: @conversation).count).to eq(1)
    expect(Message.where(conversation: @conversation, direction: 'inbound').count).to eq(1)
    expect(DiscoveryTurn.where(conversation: @conversation).count).to eq(1)
  end

  it 'admits only one of two different concurrent answers' do
    expect(race(['first-id', 'second-id']).sort).to eq([:accepted, :conflict])
    expect(Message.where(conversation: @conversation, direction: 'inbound').count).to eq(1)
  end

  it 'holds a new answer while the previous attachment is still being transcribed' do
    create(:message, conversation: @conversation, direction: 'inbound', message_type: 'audio', processing_status: 'pending', body: nil)
    expect {
      Discovery::AdmitSubmission.call(conversation: @conversation, employee: @employee, submission_id: 'after-audio', body: 'Another answer')
    }.to raise_error(Discovery::AdmitSubmission::Conflict)
    expect(EmployeeSubmission.where(conversation: @conversation)).to be_empty
  end

  it 'rejects reuse of an identity for different text after a simulated restart' do
    Discovery::AdmitSubmission.call(conversation: @conversation, employee: @employee, submission_id: 'stable', body: 'First')
    expect {
      Discovery::AdmitSubmission.call(conversation: Conversation.find(@conversation.id), employee: @employee, submission_id: 'stable', body: 'Different')
    }.to raise_error(Discovery::AdmitSubmission::Conflict)
  end
  it 'replays the same recovery job in fresh Rails processes without creating another turn or reply' do
    require 'open3'
    @company.update!(settings: @company.settings.merge('discovery_memory_retrieval_enabled' => false))
    @playbook = create(:discovery_playbook, department: 'hr', created_by_platform_user: create(:platform_user, email: "restart-#{SecureRandom.uuid}@example.com"))
    source = create(:message, conversation: @conversation, direction: 'inbound', channel: 'web', body: 'Stable original answer')
    turn = Discovery::DurableTurn.register(@conversation, source, source.body)
    script = <<~RUBY
      ActiveJob::Base.queue_adapter = :test
      class Langgraph::Client
        def run_turn!(**args)
          { 'assistant_message' => 'Restart-safe next question?', 'question_count' => 1, 'completed' => false }
        end
      end
      def OpenaiCircuitBreaker.open?; false; end
      ProcessDiscoveryTurnJob.perform_now(#{turn.id})
      puts 'RECOVERY_OK'
    RUBY
    2.times do
      stdout, stderr, status = Open3.capture3({ 'RAILS_ENV' => 'test' }, 'bundle', 'exec', 'rails', 'runner', '-', stdin_data: script)
      expect(status.success?).to be(true), stderr
      expect(stdout).to include('RECOVERY_OK')
    end
    expect(turn.reload.attempts).to eq(1)
    expect(@conversation.reload.question_count).to eq(1)
    expect(Message.where(reply_to_message_id: source.id).count).to eq(1)
    expect(source.reload.body).to eq('Stable original answer')
  end

end
