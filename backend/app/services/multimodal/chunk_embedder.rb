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
      document.document_chunks.delete_all

      chunks.each_with_index do |content, index|
        embedding = @openai.embedding(content)
        DocumentChunk.create!(
          document: @document,
          chunk_index: index,
          content: content,
          embedding: embedding,
          metadata: { "char_count" => content.length }
        )
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
