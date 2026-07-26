# frozen_string_literal: true

module Multimodal
  class ChunkEmbedder
    CHUNK_SIZE = 800
    OVERLAP = 100

    def self.call(document:, text:)
      new(document: document, text: text).call
    end

    def initialize(document:, text:)
      @document = document
      @text = text.to_s
      @openai = Openai::Client.new
    end

    def call
      chunks = split_text(@text)
      embeddings = chunks.map { |content| @openai.embedding(content) }

      # Lock the document so concurrent ingest/analysis jobs cannot interleave
      # delete_all + create! and hit the unique (document_id, chunk_index) index.
      @document.with_lock do
        @document.document_chunks.delete_all

        chunks.each_with_index do |content, index|
          DocumentChunk.create!(
            document: @document,
            chunk_index: index,
            content: content,
            embedding: embeddings[index],
            metadata: {
              "char_count" => content.length,
              "document_id" => @document.id,
              "filename" => @document.filename,
              "source" => @document.source,
              "department" => @document.department,
              "chunk_index" => index
            }
          )
        end
      end

      chunks.size
    end

    private

    def split_text(text)
      return [] if text.blank?

      parts = []
      start = 0
      while start < text.length
        chunk = text[start, CHUNK_SIZE]
        parts << chunk.strip if chunk.present?
        start += CHUNK_SIZE - OVERLAP
      end
      parts
    end
  end
end
