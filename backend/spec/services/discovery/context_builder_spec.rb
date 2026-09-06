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
    it "falls back to the code defaults" do
      expect(described_class.limits_for(company)).to eq(
        max_questions: 8,
        min_questions: 4,
        stall_turns: 2,
        slot_confidence: 0.6,
        orient_questions: 3,
        switch_after: 3
      )
    end

    it "reads an ENV override when the company has not set one" do
      # The precedence only works because these keys are absent from
      # Company::DEFAULT_SETTINGS — merged_settings would otherwise make every key
      # look operator-set and ENV could never win.
      ClimateControl.modify(DISCOVERY_MAX_QUESTIONS: "6") do
        expect(described_class.limits_for(company)[:max_questions]).to eq(6)
      end
    rescue NameError
      # No ClimateControl in this suite — set and restore by hand.
      original = ENV["DISCOVERY_MAX_QUESTIONS"]
      ENV["DISCOVERY_MAX_QUESTIONS"] = "6"
      expect(described_class.limits_for(company)[:max_questions]).to eq(6)
    ensure
      ENV["DISCOVERY_MAX_QUESTIONS"] = original if defined?(original)
    end

    it "lets a company setting beat the ENV value" do
      original = ENV["DISCOVERY_MAX_QUESTIONS"]
      ENV["DISCOVERY_MAX_QUESTIONS"] = "6"
      company.update!(settings: company.settings.merge("discovery_max_questions" => 12))

      expect(described_class.limits_for(company.reload)[:max_questions]).to eq(12)
    ensure
      ENV["DISCOVERY_MAX_QUESTIONS"] = original
    end

    it "casts the confidence threshold as a float" do
      company.update!(settings: company.settings.merge("discovery_slot_confidence" => "0.75"))
      expect(described_class.limits_for(company.reload)[:slot_confidence]).to eq(0.75)
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
      expect(context[:knowledge_snippets]).to eq([])
    end

    it "includes active knowledge snippets without requiring retrieval flag" do
      company.company_knowledge_entries.create!(
        entry_type: "process",
        title: "AP dual approval",
        content: "Invoices over 5k need two approvers",
        status: "active"
      )
      context = described_class.call(conversation: conversation, employee: employee, user_message: "hello")
      expect(context[:knowledge_snippets].first).to include("AP dual approval")
    end

    it "filters memory facts below the cosine similarity threshold" do
      company.update!(settings: company.settings.merge("discovery_memory_retrieval_enabled" => true))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")

      openai = instance_double(Openai::Client, embedding: Array.new(768, 0.1))
      allow(Openai::Client).to receive(:new).and_return(openai)

      close = double(
        "CloseFact",
        content: "Invoice approval takes three days",
        fact_type: "finding",
        department: "finance",
        neighbor_distance: 0.1
      )
      far = double(
        "FarFact",
        content: "Cafeteria menu changed",
        fact_type: "finding",
        department: "hr",
        neighbor_distance: 0.9
      )

      facts_scope = double("MemoryFactsScope")
      where_chain = double("WhereChain")
      neighbors = double("Neighbors")
      allow(company).to receive_message_chain(:company_memory_facts, :embedded).and_return(facts_scope)
      allow(facts_scope).to receive(:where).with(no_args).and_return(where_chain)
      allow(where_chain).to receive(:not).and_return(facts_scope)
      allow(facts_scope).to receive(:nearest_neighbors).and_return(neighbors)
      allow(neighbors).to receive(:first).with(3).and_return([close, far])

      context = described_class.call(
        conversation: conversation,
        employee: employee,
        user_message: "How do invoices get approved?"
      )

      expect(context[:memory_facts]).to eq([
        { content: "Invoice approval takes three days", fact_type: "finding", department: "finance" }
      ])
    end

    it "retrieves whatsapp-upload document chunks when retrieval is enabled" do
      company.update!(settings: company.settings.merge("discovery_memory_retrieval_enabled" => true))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")

      openai = instance_double(Openai::Client, embedding: Array.new(768, 0.1))
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
        embedding: Array.new(768, 0.1)
      )

      allow(DocumentChunk).to receive(:joins).and_call_original
      context = described_class.call(conversation: conversation, employee: employee, user_message: "SAP workflow")

      expect(context[:document_snippets]).to include("Manual SAP re-entry every morning")
    end

    it "builds media_context from the inbound attachment and media_snippets from whatsapp uploads" do
      company.update!(settings: company.settings.merge("discovery_memory_retrieval_enabled" => true))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")

      openai = instance_double(Openai::Client, embedding: Array.new(768, 0.1))
      allow(Openai::Client).to receive(:new).and_return(openai)

      inbound = create(:message, conversation: conversation, direction: "inbound", message_type: "image")
      create(:media_attachment,
             message: inbound,
             company: company,
             employee: employee,
             conversation: conversation,
             attachment_type: "image",
             status: "ready",
             extracted_text: "SAP invoice screen",
             structured_insights: { "summary" => "SAP invoice screen", "tools_visible" => ["SAP"] },
             confidence: 0.85,
             caption: "Our screen")

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
        content: "Earlier voice note about invoice delays",
        embedding: Array.new(768, 0.1)
      )

      context = described_class.call(
        conversation: conversation,
        employee: employee,
        user_message: "Here is the screen",
        inbound_message: inbound
      )

      expect(context[:media_context]).to include(
        type: "image",
        caption: "Our screen",
        summary: "SAP invoice screen",
        confidence: 0.85
      )
      expect(context[:media_snippets]).to include("Earlier voice note about invoice delays")
    end
  end
end
