# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multimodal::ProcessMediaService do
  let(:company) { create(:company, settings: { "discovery_media_indexing_enabled" => true }) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "discovery") }
  let(:message) do
    create(:message, conversation: conversation, direction: "inbound", message_type: "image",
                     processing_status: "pending")
  end
  let(:attachment) do
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "image",
           status: "pending",
           storage_key: "media/#{company.id}/test/image.jpg",
           caption: "Our SAP screen")
  end

  before do
    allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, download: "fake-image-bytes"))
    allow(Multimodal::UnderstandingService).to receive(:call).and_return(
      Multimodal::UnderstandingService::Result.new(
        plain_text: "SAP invoice entry screen",
        structured_insights: {
          "summary" => "SAP invoice entry screen",
          "tools_visible" => ["SAP"],
          "media_type" => "image",
          "confidence" => 0.8
        },
        confidence: 0.8
      )
    )
    allow(Multimodal::IndexMediaService).to receive(:call)
    allow(ContinueDiscoveryAfterMediaJob).to receive(:perform_later)
  end

  it "extracts content, merges caption, stores structured insights, indexes media, and enqueues discovery" do
    result = described_class.call(attachment.id)

    expect(result).to eq("Our SAP screen\n\nSAP invoice entry screen")
    expect(attachment.reload.status).to eq("ready")
    expect(attachment.structured_insights["summary"]).to eq("SAP invoice entry screen")
    expect(attachment.confidence).to eq(0.8)
    expect(message.reload.body).to eq(result)
    expect(Multimodal::IndexMediaService).to have_received(:call).with(media_attachment: attachment)
    expect(ContinueDiscoveryAfterMediaJob).to have_received(:perform_later).with(attachment.id)
  end

  it "notifies the employee and marks failed when extraction is empty" do
    attachment.update!(caption: nil)
    allow(Multimodal::UnderstandingService).to receive(:call).and_return(
      Multimodal::UnderstandingService::Result.new(plain_text: "", structured_insights: {}, confidence: nil)
    )
    expect(Multimodal::FailureNotifier).to receive(:call).with(attachment: kind_of(MediaAttachment))

    expect(described_class.call(attachment.id)).to be_nil
    expect(attachment.reload.status).to eq("failed")
    expect(ContinueDiscoveryAfterMediaJob).not_to have_received(:perform_later)
  end
end
