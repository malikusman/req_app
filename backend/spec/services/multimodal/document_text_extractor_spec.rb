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

  it "extracts shared strings from a minimal xlsx zip" do
    path = tmpdir.join("extractor-spec.xlsx").to_s
    Zip::File.open(path, Zip::File::CREATE) do |zip|
      zip.get_output_stream("xl/sharedStrings.xml") do |f|
        f.write(<<~XML)
          <?xml version="1.0"?>
          <sst><si><t>Manual spreadsheet reconciliation</t></si><si><t>SAP aging</t></si></sst>
        XML
      end
      zip.get_output_stream("xl/worksheets/sheet1.xml") do |f|
        f.write(<<~XML)
          <?xml version="1.0"?>
          <worksheet><sheetData>
            <row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row>
          </sheetData></worksheet>
        XML
      end
    end

    text = described_class.extract(
      file_path: path,
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    expect(text).to include("Manual spreadsheet reconciliation")
    expect(text).to include("SAP aging")
  end

  it "extracts paragraph text from a minimal docx zip" do
    path = tmpdir.join("extractor-spec.docx").to_s
    Zip::File.open(path, Zip::File::CREATE) do |zip|
      zip.get_output_stream("word/document.xml") do |f|
        f.write(<<~XML)
          <?xml version="1.0"?>
          <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body><w:p><w:r><w:t>Approval bottlenecks in the AP procedure</w:t></w:r></w:p></w:body>
          </w:document>
        XML
      end
    end

    text = described_class.extract(
      file_path: path,
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )

    expect(text).to include("Approval bottlenecks")
  end
end
