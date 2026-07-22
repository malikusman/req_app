# frozen_string_literal: true

require "rails_helper"

RSpec.describe Openai::Client, "OCR mock gating (BLK-1)" do
  let(:client) { described_class.new }
  let(:png_path) { Rails.root.join("tmp/blk1-ocr-spec.png").to_s }

  before do
    FileUtils.mkdir_p(Rails.root.join("tmp"))
    File.binwrite(
      png_path,
      Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    )
    allow(client).to receive(:configured?).and_return(true)
    allow(client).to receive(:api_key).and_return("sk-test")
  end

  after { FileUtils.rm_f(png_path) }

  describe "#ocr_scanned_pdf" do
    let(:pdf_path) { Rails.root.join("tmp/blk1-ocr-spec.pdf").to_s }

    before { File.write(pdf_path, "%PDF-1.4") }
    after { FileUtils.rm_f(pdf_path) }

    it "re-raises when the live OpenAI call fails and mocks are disallowed" do
      allow(MocksAllowed).to receive(:allowed?).and_return(false)
      allow(client).to receive(:post_json).and_raise(Openai::Client::Error, "500 upstream")

      expect {
        client.ocr_scanned_pdf(file_path: pdf_path)
      }.to raise_error(Openai::Client::Error, /500 upstream/)
    end

    it "returns mock text when the live call fails and mocks are allowed" do
      allow(MocksAllowed).to receive(:allowed?).and_return(true)
      allow(client).to receive(:post_json).and_raise(Openai::Client::Error, "500 upstream")

      text = client.ocr_scanned_pdf(file_path: pdf_path)

      expect(text).to include("Scanned")
    end
  end

  describe "#ocr_image" do
    it "re-raises when vision and structured fallback both fail and mocks are disallowed" do
      allow(MocksAllowed).to receive(:allowed?).and_return(false)
      allow(client).to receive(:post_json).and_raise(Openai::Client::Error, "429 rate limit")
      allow(client).to receive(:understand_image_structured).and_raise(Openai::Client::Error, "429 rate limit")

      expect {
        client.ocr_image(file_path: png_path)
      }.to raise_error(Openai::Client::Error, /429/)
    end

    it "returns mock OCR text when both paths fail and mocks are allowed" do
      allow(MocksAllowed).to receive(:allowed?).and_return(true)
      allow(client).to receive(:post_json).and_raise(Openai::Client::Error, "429 rate limit")
      allow(client).to receive(:understand_image_structured).and_raise(Openai::Client::Error, "429 rate limit")

      text = client.ocr_image(file_path: png_path)

      expect(text).to match(/POD|Excel|exception|invoice/i)
    end
  end
end
