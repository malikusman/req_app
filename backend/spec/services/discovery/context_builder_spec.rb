# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::ContextBuilder do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, department: "finance", role_title: "AP Specialist",
                      seniority: "individual_contributor",
                      metadata: { "profile" => { "responsibilities" => "Invoices", "primary_tools" => ["SAP"] } })
  end
  let(:conversation) { create(:conversation, employee: employee, status: "discovery") }

  describe ".limits_for" do
    it "reads limits from merged settings with defaults" do
      limits = described_class.limits_for(company)
      expect(limits).to eq(
        max_followup_depth: 2,
        max_questions_per_agent: 5,
        max_active_agents: 4
      )
    end

    it "honours company overrides" do
      company.update!(settings: company.settings.merge("discovery_max_followup_depth" => 1))
      expect(described_class.limits_for(company.reload)[:max_followup_depth]).to eq(1)
    end
  end

  describe "#call" do
    it "falls back to the employee profile card when the blackboard has no profile" do
      context = described_class.call(conversation: conversation, employee: employee, user_message: "hello")
      expect(context[:profile]["role_title"]).to eq("AP Specialist")
      expect(context[:blackboard]).to be_nil
    end

    it "prefers the blackboard profile when present" do
      conversation.update!(state_snapshot: { "blackboard" => { "profile" => { "role_title" => "Custom" } } })
      context = described_class.call(conversation: conversation, employee: employee, user_message: "hello")
      expect(context[:profile]).to eq("role_title" => "Custom")
      expect(context[:blackboard]).to include("profile")
    end

    it "skips retrieval when the flag is disabled" do
      context = described_class.call(conversation: conversation, employee: employee, user_message: "hello")
      expect(context[:memory_facts]).to eq([])
      expect(context[:document_snippets]).to eq([])
    end
  end
end
