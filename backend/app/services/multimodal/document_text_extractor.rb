# frozen_string_literal: true

require "pdf/reader"

module Multimodal
  class DocumentTextExtractor
    def self.extract(file_path:, content_type: nil)
      new(file_path: file_path, content_type: content_type).extract
    end

    def initialize(file_path:, content_type: nil)
      @file_path = file_path
      @content_type = content_type
    end

    def extract
      case
      when pdf?
        extract_pdf
      when text?
        File.read(@file_path)
      else
        File.read(@file_path, encoding: "UTF-8")
      rescue StandardError
        ""
      end
    end

    private

    def pdf?
      @content_type.to_s.include?("pdf") || File.extname(@file_path).downcase == ".pdf"
    end

    def text?
      %w[.txt .md .csv].include?(File.extname(@file_path).downcase)
    end

    def extract_pdf
      reader = PDF::Reader.new(@file_path)
      reader.pages.map(&:text).join("\n\n")
    rescue StandardError => e
      Rails.logger.warn("[PDF] extract failed: #{e.message}")
      ""
    end
  end
end
