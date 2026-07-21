# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multimodal::ParseDocumentService do
  let(:company) { create(:company) }
  let(:document) do
    Document.create!(
      company: company,
      filename: "pod-scan-sample.png",
      content_type: "image/png",
      status: "pending",
      storage_key: "docs/pod-scan-sample.png",
      source: "company_portal_upload",
      byte_size: 128
    )
  end

  before do
    allow(Storage::MinioClient).to receive(:new).and_return(
      instance_double(Storage::MinioClient, download: "\x89PNG\r\n\x1a\n".b)
    )
  end

  it "marks image docs ready when vision OCR returns enough text" do
    allow(Multimodal::DocumentTextExtractor).to receive(:extract).and_return(
      "POD exception note: damaged carton / short ship. AP retypes into Excel before SAP."
    )
    allow(Multimodal::ChunkEmbedder).to receive(:call).and_return(2)
    allow_any_instance_of(Openai::Client).to receive(:summarize_document).and_return(
      { "summary" => "POD exception scan", "workflows" => [], "friction_points" => [], "tools_mentioned" => [], "confidence" => 0.8 }
    )
    allow(AggregateIntelligenceJob).to receive(:perform_later)

    described_class.call(document.id)

    document.reload
    expect(document.status).to eq("ready")
    expect(document.insights_preview["source"]).to eq("vision_ocr")
    expect(document.insights_preview["chunk_count"]).to eq(2)
  end

  it "fails image docs with image_ocr_unavailable when OCR text is short" do
    allow(Multimodal::DocumentTextExtractor).to receive(:extract).and_return("short")

    expect(described_class.call(document.id)).to be_nil

    document.reload
    expect(document.status).to eq("failed")
    expect(document.processing_error).to include("image_ocr_unavailable")
  end
end
