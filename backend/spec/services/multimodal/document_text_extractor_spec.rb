# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multimodal::DocumentTextExtractor do
  let(:tmpdir) { Rails.root.join("tmp") }

  after do
    Dir.glob(tmpdir.join("extractor-spec-*")).each { |path| FileUtils.rm_f(path) }
  end

  it "returns embedded PDF text when enough characters are present" do
    path = tmpdir.join("extractor-spec-rich.pdf").to_s
    allow(PDF::Reader).to receive(:new).and_return(
      instance_double(PDF::Reader, pages: [instance_double(PDF::Reader::Page, text: "Manual SAP re-entry every morning with spreadsheet handoffs")])
    )
    File.write(path, "%PDF-1.4")

    text = described_class.extract(file_path: path, content_type: "application/pdf")

    expect(text).to include("Manual SAP re-entry")
  end

  it "falls back to OCR when PDF text is sparse" do
    path = tmpdir.join("extractor-spec-scanned.pdf").to_s
    allow(PDF::Reader).to receive(:new).and_return(
      instance_double(PDF::Reader, pages: [instance_double(PDF::Reader::Page, text: "   ")])
    )
    allow(Multimodal::OcrFallback).to receive(:extract).and_return("Scanned SOP checklist with manual Excel handoffs")
    File.write(path, "%PDF-1.4")

    text = described_class.extract(file_path: path, content_type: "application/pdf")

    expect(text).to include("Scanned SOP checklist")
  end
end
