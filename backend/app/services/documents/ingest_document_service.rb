# frozen_string_literal: true

module Documents
  # Extract text + chunk/embed only. Does not summarize or aggregate intelligence.
  # Skips re-embedding when content hash matches and chunks already exist.
  class IngestDocumentService
    MIN_TEXT_CHARS = Multimodal::ParseDocumentService::MIN_TEXT_CHARS

    def self.call(document:)
      new(document: document).call
    end

    def initialize(document:)
      @document = document
    end

    def call
      @document.update!(status: "processing", processing_error: nil)
      raw = Storage::MinioClient.new.download(@document.storage_key)
      file = Tempfile.new([@document.filename, File.extname(@document.filename)])
      file.binmode
      file.write(raw)
      file.rewind

      text = Multimodal::DocumentTextExtractor.extract(
        file_path: file.path,
        content_type: @document.content_type
      ).to_s
      text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip

      if text.length < MIN_TEXT_CHARS
        @document.update!(
          status: "failed",
          processing_error: insufficient_text_error(text.length)
        )
        return { ok: false, error: @document.processing_error, text: text }
      end

      content_hash = Digest::SHA256.hexdigest(text)
      meta = (@document.metadata || {}).stringify_keys
      prior_hash = meta["content_sha256"].to_s
      existing_chunks = @document.document_chunks.count

      if prior_hash == content_hash && existing_chunks.positive?
        preview = (@document.insights_preview || {}).merge(
          "chunk_count" => existing_chunks,
          "ingest_only" => true,
          "excerpt" => text.truncate(500),
          "content_unchanged" => true
        )
        preview["source"] = "vision_ocr" if image_document?
        @document.update!(
          insights_preview: preview,
          processing_error: nil,
          metadata: meta.merge("content_sha256" => content_hash)
        )
        return { ok: true, text: text, chunk_count: existing_chunks, skipped: true }
      end

      chunk_count = Multimodal::ChunkEmbedder.call(document: @document, text: text)
      preview = (@document.insights_preview || {}).merge(
        "chunk_count" => chunk_count,
        "ingest_only" => true,
        "excerpt" => text.truncate(500),
        "content_unchanged" => false
      )
      preview["source"] = "vision_ocr" if image_document?

      @document.update!(
        insights_preview: preview,
        processing_error: nil,
        metadata: meta.merge("content_sha256" => content_hash)
      )

      { ok: true, text: text, chunk_count: chunk_count, skipped: false }
    rescue StandardError => e
      @document.update!(status: "failed", processing_error: e.message)
      { ok: false, error: e.message }
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
        "image_ocr_unavailable: extracted #{length} characters after vision OCR (minimum #{MIN_TEXT_CHARS})."
      else
        "insufficient_text: extracted #{length} characters (minimum #{MIN_TEXT_CHARS})."
      end
    end
  end
end
