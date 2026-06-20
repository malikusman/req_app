# frozen_string_literal: true

module Multimodal
  # Vision OCR fallback when pdf-reader returns little or no text (scanned PDFs).
  class OcrFallback
    MIN_CHARS = 40

    def self.extract(file_path:, content_type: nil, language: "en")
      new(file_path: file_path, content_type: content_type, language: language).extract
    end

    def initialize(file_path:, content_type: nil, language: "en")
      @file_path = file_path
      @content_type = content_type
      @language = language
    end

    def extract
      return "" unless pdf?

      Openai::Client.new.ocr_scanned_pdf(file_path: @file_path, language: @language).to_s.strip
    rescue StandardError => e
      Rails.logger.warn("[OcrFallback] failed: #{e.message}")
      ""
    end

    private

    def pdf?
      @content_type.to_s.include?("pdf") || File.extname(@file_path).downcase == ".pdf"
    end
  end
end
