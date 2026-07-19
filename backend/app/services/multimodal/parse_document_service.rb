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

      text = DocumentTextExtractor.extract(file_path: file.path, content_type: @document.content_type).to_s.strip
      if text.length < MIN_TEXT_CHARS
        @document.update!(
          status: "failed",
          processing_error: "insufficient_text: extracted #{text.length} characters (minimum #{MIN_TEXT_CHARS}). " \
                            "Scanned PDFs, images, and slide decks often need a text-based export."
        )
        return nil
      end

      chunk_count = ChunkEmbedder.call(document: @document, text: text)

      lang = @document.company.locale
      preview = @openai.summarize_document(text, language: lang)

      @document.update!(
        status: "ready",
        insights_preview: preview.merge("chunk_count" => chunk_count),
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
  end
end
