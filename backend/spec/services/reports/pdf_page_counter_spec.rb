# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::PdfPageCounter do
  # A minimal but structurally real PDF page tree. `/Type /Pages` nodes nest, so
  # a naive scan for the first /Count finds a sub-node and under-reports —
  # exactly how `file(1)` calls a 23-page report 8 pages.
  def pdf_with(pages:, nested: false)
    objects = +"%PDF-1.4\n"
    if nested
      half = pages / 2
      objects << "1 0 obj << /Type /Pages /Count #{half} >> endobj\n"
      objects << "2 0 obj << /Type /Pages /Count #{pages - half} >> endobj\n"
    end
    objects << "3 0 obj << /Type /Pages /Count #{pages} >> endobj\n"
    pages.times { |i| objects << "#{i + 10} 0 obj << /Type /Page /Parent 3 0 R >> endobj\n" }
    objects << "%%EOF\n"
    objects
  end

  it "counts each page object" do
    expect(described_class.call(bytes: pdf_with(pages: 5))).to eq(5)
  end

  it "does not mistake the /Type /Pages tree nodes for pages" do
    expect(described_class.call(bytes: pdf_with(pages: 23, nested: true))).to eq(23)
  end

  it "falls back to the page tree when the page objects are unreadable" do
    # What a Gotenberg upgrade that compresses object streams would look like.
    bytes = "%PDF-1.7\n1 0 obj << /Type /Pages /Count 4 >> endobj\n" \
            "2 0 obj << /Type /Pages /Count 9 >> endobj\n%%EOF\n"
    expect(described_class.call(bytes: bytes)).to eq(9)
  end

  it "returns the fallback when the bytes are not a PDF" do
    # The HTML fallback path: Gotenberg down, HTML stored in the PDF's place.
    expect(described_class.call(bytes: "<html><section class='page'></section></html>", fallback: 7)).to eq(7)
  end

  it "returns the fallback for nil or empty bytes rather than raising" do
    expect(described_class.call(bytes: nil, fallback: 3)).to eq(3)
    expect(described_class.call(bytes: "", fallback: 3)).to eq(3)
  end

  it "survives binary bytes that are not valid UTF-8" do
    bytes = (+"%PDF-1.4\n\xFF\xFE\x00binary\n3 0 obj << /Type /Page >> endobj\n").force_encoding("BINARY")
    expect { described_class.call(bytes: bytes) }.not_to raise_error
    expect(described_class.call(bytes: bytes)).to eq(1)
  end
end
