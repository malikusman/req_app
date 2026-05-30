# frozen_string_literal: true

module Multimodal
  class ParseDocumentService
    def self.call(document_id)
      new(document_id).call
    end

    def initialize(document_id)
      @document = Document.find(document_id)
      @openai = Openai::Client.new
    end

    def call
      @document.update!(status: "processing")
      raw = Storage::MinioClient.new.download(@document.storage_key)
      file = Tempfile.new([@document.filename, File.extname(@document.filename)])
      file.binmode
      file.write(raw)
      file.rewind

      extraction = DocumentTextExtractor.extract_with_metadata(file_path: file.path, content_type: @document.content_type)
      text = extraction.text
      chunk_count = ChunkEmbedder.call(document: @document, text: text)

      lang = @document.company.locale
      meta = @document.metadata || {}
      preview = @openai.summarize_document(
        text,
        language: lang,
        category: meta["category"],
        admin_description: meta["admin_description"]
      )

      @document.update!(
        status: "ready",
        insights_preview: preview.merge("chunk_count" => chunk_count),
        metadata: @document.metadata.merge(extraction.metadata).merge(
          "extracted_char_count" => text.to_s.length
        )
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
