# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multimodal::IndexMediaService do
  let(:company) { create(:company, settings: { "discovery_media_indexing_enabled" => true }) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "discovery") }
  let(:message) do
    create(:message, conversation: conversation, direction: "inbound", message_type: "document", body: "Extracted PDF text about SAP workflows")
  end
  let(:attachment) do
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "document",
           status: "ready",
           extracted_text: "Extracted PDF text about SAP workflows",
           storage_key: "media/#{company.id}/test/doc.pdf",
           mime_type: "application/pdf")
  end

  before do
    allow(Multimodal::ChunkEmbedder).to receive(:call).and_return(2)
    allow(AggregateIntelligenceJob).to receive(:perform_later)
  end

  it "creates a whatsapp_upload document linked to the attachment" do
    document = described_class.call(media_attachment: attachment)

    expect(document).to be_present
    expect(document.source).to eq("whatsapp_upload")
    expect(document.status).to eq("ready")
    expect(document.message_id).to eq(message.id)
    expect(attachment.reload.document_id).to eq(document.id)
    expect(Multimodal::ChunkEmbedder).to have_received(:call).with(document: document, text: attachment.extracted_text)
    expect(AggregateIntelligenceJob).to have_received(:perform_later).with(company.id, employee.department)
  end

  it "includes caption in indexed text" do
    attachment.update!(caption: "Month-end checklist", extracted_text: "Step 1 reconcile invoices")

    described_class.call(media_attachment: attachment.reload)

    expect(Multimodal::ChunkEmbedder).to have_received(:call).with(
      hash_including(text: "Month-end checklist\n\nStep 1 reconcile invoices")
    )
  end

  it "skips indexing when the company flag is disabled" do
    company.update!(settings: company.settings.merge("discovery_media_indexing_enabled" => false))

    expect(described_class.call(media_attachment: attachment)).to be_nil
    expect(Document.count).to eq(0)
  end

  it "is idempotent when called twice" do
    described_class.call(media_attachment: attachment)
    described_class.call(media_attachment: attachment.reload)

    expect(Document.where(message_id: message.id).count).to eq(1)
  end
end
