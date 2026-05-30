# frozen_string_literal: true

require "pdf/reader"
require "zip"
require "cgi"

module Multimodal
  class DocumentTextExtractor
    Result = Struct.new(:text, :metadata, keyword_init: true)

    def self.extract(file_path:, content_type: nil)
      new(file_path: file_path, content_type: content_type).extract
    end

    def self.extract_with_metadata(file_path:, content_type: nil)
      new(file_path: file_path, content_type: content_type).extract_with_metadata
    end

    def initialize(file_path:, content_type: nil)
      @file_path = file_path
      @content_type = content_type
    end

    def extract
      extract_with_metadata.text
    end

    def extract_with_metadata
      case
      when pdf?
        pdf_text = extract_pdf
        Result.new(text: pdf_text, metadata: { "parser" => "pdf_reader", "source_type" => "pdf" })
      when docx?
        docx_text = extract_docx
        Result.new(text: docx_text, metadata: { "parser" => "docx_zip_xml", "source_type" => "docx" })
      when pptx?
        pptx_text = extract_pptx
        Result.new(text: pptx_text, metadata: { "parser" => "pptx_zip_xml", "source_type" => "pptx" })
      when text?
        Result.new(text: File.read(@file_path), metadata: { "parser" => "plain_text", "source_type" => "text" })
      else
        Result.new(
          text: File.read(@file_path, encoding: "UTF-8"),
          metadata: { "parser" => "utf8_fallback", "source_type" => "unknown" }
        )
      rescue StandardError
        Result.new(text: "", metadata: { "parser" => "fallback_failed", "source_type" => "unknown" })
      end
    end

    private

    def pdf?
      @content_type.to_s.include?("pdf") || File.extname(@file_path).downcase == ".pdf"
    end

    def text?
      %w[.txt .md .csv].include?(File.extname(@file_path).downcase)
    end

    def docx?
      @content_type.to_s.include?("wordprocessingml.document") || File.extname(@file_path).downcase == ".docx"
    end

    def pptx?
      @content_type.to_s.include?("presentationml.presentation") || File.extname(@file_path).downcase == ".pptx"
    end

    def extract_pdf
      reader = PDF::Reader.new(@file_path)
      reader.pages.map(&:text).join("\n\n")
    rescue StandardError => e
      Rails.logger.warn("[PDF] extract failed: #{e.message}")
      ""
    end

    def extract_docx
      extract_zip_xml("word/document.xml")
    end

    def extract_pptx
      parts = []
      Zip::File.open(@file_path) do |zip|
        zip.glob("ppt/slides/slide*.xml").sort_by(&:name).each do |entry|
          parts << xml_to_text(entry.get_input_stream.read)
        end
      end
      parts.join("\n\n")
    rescue StandardError => e
      Rails.logger.warn("[PPTX] extract failed: #{e.message}")
      ""
    end

    def extract_zip_xml(path)
      Zip::File.open(@file_path) do |zip|
        entry = zip.find_entry(path)
        return "" unless entry

        xml_to_text(entry.get_input_stream.read)
      end
    rescue StandardError => e
      Rails.logger.warn("[DOCX] extract failed: #{e.message}")
      ""
    end

    def xml_to_text(xml)
      stripped = xml.gsub(/<[^>]+>/, " ")
      CGI.unescapeHTML(stripped).gsub(/\s+/, " ").strip
    end
  end
end
