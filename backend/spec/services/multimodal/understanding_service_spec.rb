# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multimodal::UnderstandingService do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) { create(:conversation, employee: employee, company: company) }
  let(:message) { create(:message, conversation: conversation, direction: "inbound", message_type: "image") }
  let(:attachment) do
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "image",
           caption: "Invoice screen")
  end
  let(:file_path) { Rails.root.join("tmp/test-image.jpg").to_s }

  before do
    File.binwrite(file_path, "fake-image")
  end

  after do
    FileUtils.rm_f(file_path)
  end

  it "returns structured image insights" do
    openai = instance_double(
      Openai::Client,
      understand_image_structured: {
        "summary" => "SAP invoice entry screen",
        "tools_visible" => ["SAP"],
        "process_steps" => ["Manual entry"],
        "pain_points" => ["Slow UI"],
        "confidence" => 0.82
      }
    )
    allow(Openai::Client).to receive(:new).and_return(openai)

    result = described_class.call(attachment: attachment, file_path: file_path)

    expect(result.plain_text).to eq("SAP invoice entry screen")
    expect(result.structured_insights).to include("media_type" => "image", "summary" => "SAP invoice entry screen")
    expect(result.confidence).to eq(0.82)
  end

  it "returns structured document insights from extracted text" do
    attachment.update!(attachment_type: "document", mime_type: "application/pdf")
    allow(Multimodal::DocumentTextExtractor).to receive(:extract).and_return("Month-end close checklist with Excel handoffs")
    openai = instance_double(
      Openai::Client,
      understand_document_structured: {
        "summary" => "Month-end close process",
        "workflows" => ["Close checklist"],
        "friction_points" => ["Excel handoffs"],
        "tools_mentioned" => ["Excel"],
        "confidence" => 0.78
      }
    )
    allow(Openai::Client).to receive(:new).and_return(openai)

    result = described_class.call(attachment: attachment, file_path: file_path)

    expect(result.plain_text).to include("Month-end close process")
    expect(result.structured_insights["media_type"]).to eq("document")
    expect(result.confidence).to eq(0.78)
  end
end
