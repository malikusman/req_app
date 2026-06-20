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

    it "retrieves whatsapp-upload document chunks when retrieval is enabled" do
      company.update!(settings: company.settings.merge("discovery_memory_retrieval_enabled" => true))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")

      openai = instance_double(Openai::Client, embedding: Array.new(1536, 0.1))
      allow(Openai::Client).to receive(:new).and_return(openai)

      doc = company.documents.create!(
        employee: employee,
        conversation: conversation,
        source: "whatsapp_upload",
        filename: "whatsapp-doc.pdf",
        content_type: "application/pdf",
        byte_size: 100,
        storage_key: "media/test/doc.pdf",
        status: "ready"
      )
      DocumentChunk.create!(
        document: doc,
        chunk_index: 0,
        content: "Manual SAP re-entry every morning",
        embedding: Array.new(1536, 0.1)
      )

      allow(DocumentChunk).to receive(:joins).and_call_original
      context = described_class.call(conversation: conversation, employee: employee, user_message: "SAP workflow")

      expect(context[:document_snippets]).to include("Manual SAP re-entry every morning")
    end
  end
end
