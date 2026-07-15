# frozen_string_literal: true

module Catalog
  class HybridMatcher
    MAX_RESULTS = 5

    def self.call(query:, tags: [], keywords: [], embedding: nil, limit: MAX_RESULTS)
      new(query: query, tags: tags, keywords: keywords, embedding: embedding, limit: limit).call
    end

    def initialize(query:, tags: [], keywords: [], embedding: nil, limit: MAX_RESULTS)
      @query = query.to_s
      @tags = Array(tags).map(&:to_s)
      @keywords = Array(keywords).map(&:to_s)
      @embedding = embedding
      @limit = limit
    end

    def call
      entries = SolutionCatalogEntry.active.to_a
      scored = entries.map { |entry| score_entry(entry) }.select { |m| m[:score].positive? }
      scored.sort_by { |m| -m[:score] }.first(@limit)
    end

    private

    def score_entry(entry)
      reasons = []
      score = 0.0

      entry_tags = Array(entry.tags).map(&:to_s)
      tag_hits = (@tags & entry_tags)
      if tag_hits.any?
        score += 0.35 * (tag_hits.size.to_f / [@tags.size, 1].max)
        reasons << "tag_match:#{tag_hits.join(',')}"
      end

      entry_keywords = Array(entry.match_keywords).map { |k| k.to_s.downcase }
      query_blob = [@query, *@keywords].join(" ").downcase
      keyword_hits = entry_keywords.select { |kw| kw.present? && query_blob.include?(kw) }
      if keyword_hits.any?
        score += 0.35 * [keyword_hits.size / 3.0, 1.0].min
        reasons << "keyword_match:#{keyword_hits.first(3).join(',')}"
      end

      if entry.name.present? && @query.present? && entry.name.downcase.include?(@query.downcase)
        score += 0.15
        reasons << "name_contains_query"
      end

      if @embedding.present? && entry.respond_to?(:embedding) && entry.embedding.present?
        sim = cosine_similarity(@embedding, entry.embedding)
        if sim > 0.2
          score += 0.35 * sim
          reasons << "embedding_similarity:#{sim.round(3)}"
        end
      end

      {
        solution_catalog_entry_id: entry.id,
        id: entry.id,
        name: entry.name,
        vendor: entry.vendor,
        category: entry.category,
        url: entry.website_url,
        website_url: entry.website_url,
        partnership_tier: entry.partnership_tier,
        entity_type: entry.try(:entity_type),
        score: score.round(4),
        reason: reasons.join("; ").presence || "no_match"
      }
    end

    def cosine_similarity(a, b)
      a = Array(a).map(&:to_f)
      b = Array(b).map(&:to_f)
      return 0.0 if a.empty? || b.empty? || a.size != b.size

      dot = 0.0
      na = 0.0
      nb = 0.0
      a.each_with_index do |av, i|
        bv = b[i]
        dot += av * bv
        na += av * av
        nb += bv * bv
      end
      denom = Math.sqrt(na) * Math.sqrt(nb)
      return 0.0 if denom.zero?

      dot / denom
    end
  end
end
