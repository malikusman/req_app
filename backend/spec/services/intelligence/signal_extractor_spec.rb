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

  it "captures inbound message excerpts as source evidence" do
    create(:message,
           conversation: conversation,
           direction: "inbound",
           body: "I spend hours in Excel copying data manually every week")

    signals = described_class.call(company: company)
    manual = signals.find { |s| s[:signal_type] == "manual_process" }

    expect(manual).to be_present
    expect(manual[:source_excerpts].size).to eq(1)
    expect(manual[:source_excerpts].first[:excerpt]).to include("Excel")
  end

  describe "unfinished interviews" do
    def unfinished(question_count)
      create(:conversation, employee: create(:employee, company: company, department: "finance"),
                            company: company, status: "abandoned", question_count: question_count)
    end

    it "count what someone said before leaving, once they got past the opening, at half weight" do
      create(:message, conversation: unfinished(4), direction: "inbound",
                       body: "I spend hours in Excel copying data manually every week")
      create(:message, conversation: unfinished(1), direction: "inbound",
                       body: "Everything is manual spreadsheet work here")

      manual = described_class.call(company: company).find { |s| s[:signal_type] == "manual_process" }

      expect(manual[:source_excerpts].size).to eq(1)
      expect(manual[:source_excerpts].first).to include(partial: true)
      expect(manual[:strength]).to be < 0.2 + 0.001 # one half-weight message stays at the floor
    end

    it "weigh a finished interview's answers above an unfinished one's" do
      said = ["I spend hours in Excel copying data manually", "Then I re-enter it all by hand",
              "The spreadsheet has to be rebuilt every Monday"]
      said.each { |body| create(:message, conversation: conversation, direction: "inbound", body: body) }
      finished = described_class.call(company: company).find { |s| s[:signal_type] == "manual_process" }[:strength]

      Message.delete_all
      left = unfinished(4)
      said.each { |body| create(:message, conversation: left, direction: "inbound", body: body) }
      partial = described_class.call(company: company).find { |s| s[:signal_type] == "manual_process" }[:strength]

      expect(partial).to be < finished
    end
  end
end
