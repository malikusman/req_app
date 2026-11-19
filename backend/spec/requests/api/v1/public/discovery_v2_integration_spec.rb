require 'rails_helper'

RSpec.describe 'Employee Discovery V2 HTTP integration', type: :request do
  it 'runs all four phases through Rails, durable jobs, HTTP FastAPI/LangGraph and confirmed completion' do
    endpoint = ENV['V2_INTEGRATION_AGENT_URL']
    skip 'Start agent/tests/v2_integration_server.py and set V2_INTEGRATION_AGENT_URL (provider is stubbed)' unless endpoint
    WebMock.disable_net_connect!(allow_localhost: true, allow: URI(endpoint).host)
    company = create(:company)
    employee = create(:employee, company: company, onboarding_step: 'verified', participation_status: 'started', department: 'finance', role_title: 'Finance assistant')
    conversation = create(:conversation, employee: employee, company: company, status: 'discovery', question_count: 0, langgraph_thread_id: SecureRandom.uuid)
    session = create(:employee_web_session, employee: employee, company: company, verified_at: Time.current)
    headers = employee_web_headers(session: session, employee: employee)
    create(:discovery_playbook, department: 'finance')
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow(Langgraph::Client).to receive(:new).and_wrap_original { |original, *args| original.call(base_url: endpoint) }
    DiscoveryRequest.set(admitting: true) do
      Whatsapp::ProfilingHandler.new(employee: employee, conversation: conversation, channel: 'web', client: Web::CapturingMetaClient.new).start!
    end
    turn = conversation.discovery_turns.order(:id).last
    expect(turn).to be_present
    source = turn.source_message
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    expect(turn.reload.status).to eq('succeeded'), turn.error_code
    expect(conversation.reload.blackboard.dig('employee_discovery_v2', 'phase')).to eq('anchor')
    expect(conversation.messages.where(direction: 'outbound').pluck(:body).join(' ')).not_to include('what do you spend most of your time on')
    %w[pause continue].each do |command|
      post '/api/v1/public/discover/messages', params: { body: command, submission_id: SecureRandom.uuid }, headers: headers
      expect(response).to have_http_status(:ok)
      turn = conversation.discovery_turns.order(:id).last
      ProcessDiscoveryTurnJob.perform_now(turn.id)
      expect(turn.reload.status).to eq('succeeded'), turn.error_code
      get '/api/v1/public/discover/messages', headers: headers
      expect(response.parsed_body['state']['interview_paused']).to eq(command == 'pause')
      expect(conversation.reload.question_count).to eq(1)
    end
    answers = ['Review invoices daily for 20 to 30 minutes', 'Prepare reports weekly for 10 to 15 minutes',
      'No monthly or quarter-end work', 'No seasonal work', 'Nothing takes longer than expected', 'No duplicate entry',
      'No chasing or waiting', 'No extra trust checking', 'Retype prices outside our systems', 'No AI tools',
      'Prices are weekly, 5 to 10 minutes']
    phases = ['anchor']
    answers.each do |answer|
      id = SecureRandom.uuid
      2.times do
        post '/api/v1/public/discover/messages', params: { body: answer, submission_id: id }, headers: headers
        expect(response).to have_http_status(:ok), response.body
      end
      source = EmployeeSubmission.find_by!(conversation: conversation, submission_id: id).message
      turn = DiscoveryTurn.find_by!(source_message: source)
      2.times { ProcessDiscoveryTurnJob.perform_now(turn.id) }
      expect(turn.reload.status).to eq('succeeded'), turn.error_code
      expect(conversation.messages.where(reply_to_message_id: source.id).count).to eq(1)
      data = conversation.reload.blackboard['employee_discovery_v2']
      phases << data['phase']
      expect(conversation.status).to eq('discovery')
    end
    data = conversation.blackboard['employee_discovery_v2']
    expect(phases.uniq).to eq(%w[anchor inventory invisible_work size_close])
    expect(data['presented_summary']['text']).to include('Retype prices', '5–10')
    post '/api/v1/public/discover/messages', params: { body: 'Yes, that is correct', submission_id: SecureRandom.uuid }, headers: headers
    turn = conversation.discovery_turns.order(:id).last
    ProcessDiscoveryTurnJob.perform_now(turn.id)
    expect(turn.reload.status).to eq('succeeded'), turn.error_code
    expect(conversation.reload.status).to eq('completed')
    expect(employee.reload.participation_status).to eq('completed')
    data = conversation.blackboard['employee_discovery_v2']
    expect(data['outcome']).to eq('successful')
    expect(data['canonical_work_items'].size).to eq(3)
    expect(data['evidence_references'].all? { |e| e['source_id'] && e['company_id'] == company.id }).to be(true)
    expect(TaskSources::SyncFromConversation.call(conversation: conversation).size).to eq(3)
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
