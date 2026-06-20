# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/full_cycle_simulator")

RSpec.describe FullCycleSimulator do
  let(:company) { create(:company, :onboarded, settings: Company::DEFAULT_SETTINGS.merge(
    "discovery_profiling_enabled" => true,
    "discovery_multi_agent_enabled" => true,
    "discovery_multimodal_enabled" => true,
    "discovery_media_indexing_enabled" => true,
    "discovery_memory_retrieval_enabled" => true
  )) }
  let(:employee) { create(:employee, company: company, phone_e164: "+14155559901", participation_status: "completed") }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed", state_snapshot: {}) }
  let(:simulator) do
    described_class.new(slug: company.slug, persona: "finance_ic", cleanup: false).tap do |s|
      s.instance_variable_set(:@company, company)
      s.instance_variable_set(:@employee, employee)
      s.instance_variable_set(:@conversation, conversation)
      s.instance_variable_set(:@checks, [])
    end
  end

  it "validates multimodal pipeline stages" do
    allow(simulator).to receive(:simulate_multimodal_inbound) do |type, **_opts|
      message = create(:message, conversation: conversation, direction: "inbound", message_type: type)
      create(:media_attachment,
             message: message,
             company: company,
             employee: employee,
             conversation: conversation,
             attachment_type: type,
             status: "ready",
             storage_key: "dev/simulated/#{SecureRandom.hex(4)}",
             extracted_text: "Manual SAP spreadsheet re-entry every morning",
             structured_insights: { "summary" => "SAP invoice screen", "pain_points" => ["Manual data entry"] },
             confidence: 0.85)
      conversation.update!(state_snapshot: conversation.state_snapshot.merge("had_multimodal" => true))
      company.documents.create!(
        employee: employee,
        conversation: conversation,
        message: message,
        source: "whatsapp_upload",
        filename: "whatsapp-#{type}.pdf",
        content_type: "application/pdf",
        byte_size: 100,
        storage_key: "media/test.pdf",
        status: "ready"
      )
    end

    simulator.send(:run_multimodal!)

    checks = simulator.instance_variable_get(:@checks)
    expect(checks.all? { |_, passed| passed }).to be(true)
  end
end
