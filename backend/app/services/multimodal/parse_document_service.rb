# frozen_string_literal: true

module Multimodal
  class ParseDocumentService
    MIN_TEXT_CHARS = 40

    def self.call(document_id)
      new(document_id).call
    end

    def initialize(document_id)
      @document = Document.find(document_id)
      @openai = Openai::Client.new
    end

    def call
      @document.update!(status: "processing", processing_error: nil)
      raw = Storage::MinioClient.new.download(@document.storage_key)
      file = Tempfile.new([@document.filename, File.extname(@document.filename)])
      file.binmode
      file.write(raw)
      file.rewind

      text = DocumentTextExtractor.extract(file_path: file.path, content_type: @document.content_type).to_s
      text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip
      if text.length < MIN_TEXT_CHARS
        @document.update!(
          status: "failed",
          processing_error: insufficient_text_error(text.length)
        )
        return nil
      end

      chunk_count = ChunkEmbedder.call(document: @document, text: text)

      lang = @document.company.locale
      preview = @openai.summarize_document(text, language: lang)
      preview = preview.merge("chunk_count" => chunk_count)
      preview = preview.merge("source" => "vision_ocr") if image_document?

      @document.update!(
        status: "ready",
        insights_preview: preview,
        processing_error: nil
      )

      AggregateIntelligenceJob.perform_later(@document.company_id, @document.department)
      preview
    rescue StandardError => e
      @document.update!(status: "failed", processing_error: e.message)
      raise
    ensure
      file&.close
      file&.unlink
    end

    private

    def image_document?
      ct = @document.content_type.to_s
      ct.start_with?("image/") || %w[.png .jpg .jpeg .webp .gif].include?(File.extname(@document.filename.to_s).downcase)
    end

    def insufficient_text_error(length)
      if image_document?
        "image_ocr_unavailable: extracted #{length} characters after vision OCR (minimum #{MIN_TEXT_CHARS}). " \
          "Ensure OPENAI_API_KEY is configured, or upload a clearer scan / text export."
      else
        "insufficient_text: extracted #{length} characters (minimum #{MIN_TEXT_CHARS}). " \
          "Scanned PDFs, images, and slide decks often need a text-based export."
      end
    end
  end
end
