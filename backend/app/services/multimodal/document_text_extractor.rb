# frozen_string_literal: true

require "pdf/reader"
require "zip"

module Multimodal
  class DocumentTextExtractor
    MIN_PDF_TEXT_CHARS = 40

    def self.extract(file_path:, content_type: nil)
      new(file_path: file_path, content_type: content_type).extract
    end

    def initialize(file_path:, content_type: nil)
      @file_path = file_path
      @content_type = content_type.to_s
      @ext = File.extname(file_path).downcase
    end

    def extract
      case
      when pdf?
        extract_pdf
      when image?
        extract_image
      when text?
        File.read(@file_path)
      when xlsx?
        extract_xlsx
      when docx?
        extract_docx
      else
        safe_binary_fallback
      end
    end

    private

    def pdf?
      @content_type.include?("pdf") || @ext == ".pdf"
    end

    def image?
      @content_type.start_with?("image/") || %w[.png .jpg .jpeg .webp .gif].include?(@ext)
    end

    def text?
      %w[.txt .md .csv].include?(@ext)
    end

    def xlsx?
      @ext == ".xlsx" || @content_type.include?("spreadsheetml") || @content_type.include?("excel")
    end

    def docx?
      @ext == ".docx" || @content_type.include?("wordprocessingml")
    end

    def extract_pdf
      reader = PDF::Reader.new(@file_path)
      text = reader.pages.map(&:text).join("\n\n").strip
      return text if text.length >= MIN_PDF_TEXT_CHARS

      ocr_text = OcrFallback.extract(file_path: @file_path, content_type: @content_type)
      combined = [text, ocr_text].map(&:presence).compact.join("\n\n")
      combined.presence || text
    rescue StandardError
      OcrFallback.extract(file_path: @file_path, content_type: @content_type).to_s
    end

    def extract_image
      OcrFallback.extract(file_path: @file_path, content_type: @content_type).to_s
    end

    # Never return invalid UTF-8 to callers — .strip on bad encoding raises ArgumentError.
    def safe_binary_fallback
      raw = File.binread(@file_path)
      text = raw.force_encoding("UTF-8")
      text = text.scrub("") unless text.valid_encoding?
      text
    rescue StandardError
      ""
    end

    # Minimal OOXML extractors — enough for procedures / financial exports without heavy gems.
    def extract_xlsx
      shared = []
      cells = []
      Zip::File.open(@file_path) do |zip|
        if (entry = zip.find_entry("xl/sharedStrings.xml"))
          xml = entry.get_input_stream.read
          shared = xml.scan(/<t[^>]*>([^<]*)<\/t>/).flatten
        end
        sheet = zip.find_entry("xl/worksheets/sheet1.xml") ||
                zip.glob("xl/worksheets/*.xml").first
        if sheet
          xml = sheet.get_input_stream.read
          xml.scan(/<c[^>]*t="s"[^>]*>\s*<v>(\d+)<\/v>/).each do |(idx)|
            cells << shared[idx.to_i]
          end
          xml.scan(/<c[^>]*>\s*<v>([^<]+)<\/v>/).each do |(val)|
            cells << val unless val.match?(/\A\d+\z/) && shared[val.to_i]
          end
        end
      end
      cells.compact.map(&:to_s).map(&:strip).reject(&:blank?).uniq.join("\n")
    rescue StandardError
      ""
    end

    def extract_docx
      Zip::File.open(@file_path) do |zip|
        entry = zip.find_entry("word/document.xml")
        return "" unless entry

        xml = entry.get_input_stream.read
        xml.scan(/<w:t[^>]*>([^<]*)<\/w:t>/).flatten.join(" ").squeeze(" ").strip
      end
    rescue StandardError
      ""
    end
  end
end
