# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::SignalExtractor do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }
  let(:message) { create(:message, conversation: conversation, direction: "inbound", message_type: "image") }

  it "links matching media attachments as multimodal evidence" do
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "image",
           status: "ready",
           extracted_text: "Manual SAP re-entry every morning",
           structured_insights: {
             "summary" => "SAP invoice screen with manual copy-paste",
             "pain_points" => ["Manual spreadsheet work"]
           },
           confidence: 0.9)

    signals = described_class.call(company: company)
    manual = signals.find { |s| s[:signal_type] == "manual_process" }

    expect(manual).to be_present
    expect(manual[:multimodal_evidence].size).to eq(1)
    expect(manual[:multimodal_evidence].first[:attachment_type]).to eq("image")
  end

  it "persists merged multimodal evidence via SignalUpsertService" do
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "document",
           status: "ready",
           extracted_text: "We wait days for manager approval on every invoice",
           structured_insights: { "summary" => "Approval queue in SAP" },
           confidence: 0.8)

    signals = described_class.call(company: company)
    Intelligence::SignalUpsertService.call(company: company, signals: signals, department: "finance")

    signal = company.company_signals.find_by(signal_type: "approval_bottleneck")
    expect(signal.metadata["multimodal_evidence"]).to be_present
    expect(signal.metadata["multimodal_evidence"].first["attachment_type"]).to eq("document")
  end
end
