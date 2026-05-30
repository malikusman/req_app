# frozen_string_literal: true

module Knowledge
  class SemanticSearch
    DEFAULT_LIMIT = 8
    SCORE_THRESHOLD = 0.55

    def self.call(company:, query:, limit: DEFAULT_LIMIT, source_types: nil)
      new(company: company, query: query, limit: limit, source_types: source_types).call
    end

    def initialize(company:, query:, limit: DEFAULT_LIMIT, source_types: nil)
      @company = company
      @query = query.to_s.strip
      @limit = limit
      @source_types = source_types
    end

    def call
      return [] if @query.blank?

      embedding = Openai::Client.new.embedding(@query)
      return [] if embedding.blank?

      doc_results = search_document_chunks(embedding)
      knowledge_results = search_knowledge_chunks(embedding)

      (doc_results + knowledge_results)
        .sort_by { |r| -r[:score] }
        .first(@limit)
    end

    private

    def search_document_chunks(embedding)
      scope = DocumentChunk
              .joins(:document)
              .where(documents: { company_id: @company.id, status: "ready" })
              .where.not(embedding: nil)

      scope.nearest_neighbors(:embedding, embedding, distance: "cosine")
           .limit(@limit * 2)
           .map { |chunk| format_document_chunk(chunk) }
           .select { |r| r[:score] >= SCORE_THRESHOLD }
    end

    def search_knowledge_chunks(embedding)
      scope = KnowledgeChunk.where(company_id: @company.id).where.not(embedding: nil)
      scope = scope.where(source_type: @source_types) if @source_types.present?

      scope.nearest_neighbors(:embedding, embedding, distance: "cosine")
           .limit(@limit * 2)
           .map { |chunk| format_knowledge_chunk(chunk) }
           .select { |r| r[:score] >= SCORE_THRESHOLD }
    end

    def format_document_chunk(chunk)
      doc = chunk.document
      meta = doc.metadata || {}
      score = chunk.respond_to?(:neighbor_distance) ? (1 - chunk.neighbor_distance.to_f) : 0.0

      {
        source_type: "document",
        source_id: doc.id,
        chunk_id: chunk.id,
        title: doc.filename,
        content: chunk.content.truncate(1200),
        score: score.round(4),
        metadata: {
          category: meta["category"],
          department: doc.department
        }
      }
    end

    def format_knowledge_chunk(chunk)
      score = chunk.respond_to?(:neighbor_distance) ? (1 - chunk.neighbor_distance.to_f) : 0.0

      {
        source_type: chunk.source_type,
        source_id: chunk.source_id,
        chunk_id: chunk.id,
        title: chunk.metadata["title"],
        content: chunk.content.truncate(1200),
        score: score.round(4),
        metadata: chunk.metadata
      }
    end
  end
end
