# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::ProfilingHandler do
  let(:company) do
    create(:company).tap do |c|
      c.update!(settings: c.settings.merge(
        "discovery_profiling_enabled" => true,
        "discovery_multi_agent_enabled" => false
      ))
    end
  end
  let(:employee) do
    create(:employee, company: company, department: nil, role_title: nil, seniority: nil,
                      display_name: "Sam", onboarding_step: "verified")
  end
  let(:conversation) { create(:conversation, employee: employee, status: "profiling", question_count: 0) }
  let(:meta_client) { instance_double(Whatsapp::MetaClient, configured?: false) }

  subject(:handler) { described_class.new(employee: employee, conversation: conversation, client: meta_client) }

  before { create(:discovery_playbook, department: "default") }

  describe ".enabled?" do
    it "reflects the company setting" do
      expect(described_class.enabled?(company)).to be(true)
      company.update!(settings: company.settings.merge("discovery_profiling_enabled" => false))
      expect(described_class.enabled?(company.reload)).to be(false)
    end
  end

  describe "#start!" do
    it "asks the first pending profiling question" do
      handler.start!

      expect(conversation.reload.status).to eq("profiling")
      expect(conversation.state_snapshot.dig("profiling", "step")).to eq("role_title")
      bodies = conversation.messages.where(direction: "outbound").pluck(:body)
      expect(bodies.last).to include("job title")
    end
  end

  describe "#handle_inbound_text" do
    before { handler.start! }

    it "captures answers and advances through the steps" do
      handler.handle_inbound_text("Accounts Payable Specialist")
      expect(employee.reload.role_title).to eq("Accounts Payable Specialist")
      expect(conversation.reload.state_snapshot.dig("profiling", "step")).to eq("department")

      handler.handle_inbound_text("Finance")
      expect(employee.reload.department).to eq("finance")

      handler.handle_inbound_text("individual contributor")
      expect(employee.reload.seniority).to eq("individual_contributor")
    end

    it "parses seniority keywords with the most senior match winning" do
      handler.handle_inbound_text("AP Specialist")
      handler.handle_inbound_text("Finance")
      handler.handle_inbound_text("I'm the CFO, an executive")
      expect(employee.reload.seniority).to eq("executive")
    end

    it "skips team_size for individual contributors and completes into discovery" do
      allow(Discovery::ProactiveStartService).to receive(:call)

      handler.handle_inbound_text("AP Specialist")
      handler.handle_inbound_text("Finance")
      handler.handle_inbound_text("individual contributor")
      handler.handle_inbound_text("I process invoices and chase approvals")
      handler.handle_inbound_text("SAP, Excel and Slack")

      employee.reload
      expect(employee.profile_data["responsibilities"]).to include("process invoices")
      expect(employee.profile_data["primary_tools"]).to eq(["SAP", "Excel", "Slack"])
      expect(employee.profile_data).not_to have_key("team_size")
      expect(employee.profile_complete?).to be(true)

      conversation.reload
      expect(conversation.status).to eq("discovery")
      expect(conversation.blackboard["profile"]).to include("role_title" => "AP Specialist")
      expect(Discovery::ProactiveStartService).to have_received(:call).with(
        hash_including(conversation: conversation, employee: employee)
      )
    end

    it "asks team_size for managers" do
      handler.handle_inbound_text("Head of HR Ops")
      handler.handle_inbound_text("HR")
      handler.handle_inbound_text("I'm a manager")
      handler.handle_inbound_text("Onboarding and people processes")

      expect(conversation.reload.state_snapshot.dig("profiling", "step")).to eq("team_size")

      allow(Discovery::ProactiveStartService).to receive(:call)

      handler.handle_inbound_text("about 6 people")
      expect(employee.reload.profile_data["team_size"]).to eq(6)
    end

    it "handles opt-out" do
      handler.handle_inbound_text("STOP")
      expect(employee.reload.participation_status).to eq("declined")
      expect(conversation.reload.status).to eq("abandoned")
    end

    it "requests agent routing when multi-agent is enabled" do
      company.update!(settings: company.settings.merge("discovery_multi_agent_enabled" => true))
      client = instance_double(Langgraph::Client)
      allow(Langgraph::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create_thread!).and_return(SecureRandom.uuid)
      allow(client).to receive(:route!).and_return(
        "agents" => [{ "id" => "domain_finance", "priority" => 1, "question_budget" => 4 }],
        "skipped" => [],
        "total_budget" => 4
      )
      allow(Discovery::ProcessTurnService).to receive(:call).and_return(
        { "assistant_message" => "Q", "completed" => false, "question_count" => 1 }
      )

      handler.handle_inbound_text("AP Specialist")
      handler.handle_inbound_text("Finance")
      handler.handle_inbound_text("individual contributor")
      handler.handle_inbound_text("I process invoices")
      handler.handle_inbound_text("SAP")

      expect(client).to have_received(:route!)
      expect(conversation.reload.blackboard["agent_queue"].first["id"]).to eq("domain_finance")
    end
  end
end
