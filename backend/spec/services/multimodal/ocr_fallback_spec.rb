# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multimodal::OcrFallback do
  let(:tmpdir) { Rails.root.join("tmp") }
  let(:png_path) { tmpdir.join("ocr-fallback-spec.png").to_s }

  before do
    File.binwrite(
      png_path,
      Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    )
  end

  after { FileUtils.rm_f(png_path) }

  it "calls Openai::Client#ocr_image for PNG uploads" do
    client = instance_double(Openai::Client)
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(client).to receive(:ocr_image).and_return("Handwritten POD: short ship noted")

    text = described_class.extract(file_path: png_path, content_type: "image/png")

    expect(text).to include("Handwritten POD")
    expect(client).to have_received(:ocr_image).with(hash_including(file_path: png_path))
  end

  it "keeps PDF path on ocr_scanned_pdf" do
    pdf_path = tmpdir.join("ocr-fallback-spec.pdf").to_s
    File.write(pdf_path, "%PDF-1.4")
    client = instance_double(Openai::Client)
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(client).to receive(:ocr_scanned_pdf).and_return("Scanned SOP text")

    text = described_class.extract(file_path: pdf_path, content_type: "application/pdf")

    expect(text).to include("Scanned SOP")
    expect(client).to have_received(:ocr_scanned_pdf)
    FileUtils.rm_f(pdf_path)
  end

  it "returns empty string when OCR raises so ParseDocumentService can mark failed" do
    client = instance_double(Openai::Client)
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(client).to receive(:ocr_image).and_raise(Openai::Client::Error, "OpenAI unavailable")

    text = described_class.extract(file_path: png_path, content_type: "image/png")

    expect(text).to eq("")
  end
end
