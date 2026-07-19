# frozen_string_literal: true

module Multimodal
  # Vision OCR fallback when pdf-reader returns little text, or for portal image uploads.
  class OcrFallback
    MIN_CHARS = 40

    def self.extract(file_path:, content_type: nil, language: "en")
      new(file_path: file_path, content_type: content_type, language: language).extract
    end

    def initialize(file_path:, content_type: nil, language: "en")
      @file_path = file_path
      @content_type = content_type.to_s
      @language = language
    end

    def extract
      client = Openai::Client.new
      text = if pdf?
               client.ocr_scanned_pdf(file_path: @file_path, language: @language)
             elsif image?
               client.ocr_image(file_path: @file_path, language: @language)
             else
               ""
             end
      text.to_s.strip
    rescue StandardError => e
      Rails.logger.warn("[OcrFallback] failed: #{e.message}")
      ""
    end

    private

    def pdf?
      @content_type.include?("pdf") || File.extname(@file_path).downcase == ".pdf"
    end

    def image?
      return true if @content_type.start_with?("image/")

      %w[.png .jpg .jpeg .webp .gif].include?(File.extname(@file_path).downcase)
    end
  end
end
