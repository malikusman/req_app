# frozen_string_literal: true

module Reports
  # Turns the structured, evidence-derived snapshot into a consulting-grade
  # narrative (pyramid executive summary, quantified-but-hedged implications,
  # phased roadmap) using an LLM — grounded strictly in the snapshot.
  #
  # Fails safe: returns nil on any problem so the caller keeps the deterministic
  # prose. Only calls the model when the client is genuinely configured (a real
  # OpenAI key OR a local OpenAI-compatible endpoint with a dummy key), so a
  # production instance without a key never fabricates a narrative.
  class NarrativeWriter
    def self.call(company:, snapshot:)
      new(company: company, snapshot: snapshot).call
    end

    def initialize(company:, snapshot:)
      @company = company
      @snapshot = snapshot
    end

    def call
      return nil unless enabled?

      client = Openai::Client.new
      return nil unless client.configured?

      parsed = client.report_narrative(context: evidence_context, language: @company.locale.presence || "en")
      normalize(parsed)
    rescue StandardError => e
      Rails.logger.warn("[Reports::NarrativeWriter] falling back to deterministic prose: #{e.class}: #{e.message}")
      nil
    end

    private

    # Off only when explicitly disabled. Local Gemma testing works by pointing
    # OPENAI_BASE_URL at the local endpoint and setting a dummy OPENAI_API_KEY.
    def enabled?
      ENV.fetch("AI_REPORT_NARRATIVE", "true").to_s.downcase != "false"
    end

    # Compact, evidence-only context. No raw PII; just the structured findings
    # the report already stands on.
    def evidence_context
      {
        "company" => @snapshot["company"]&.slice("name", "profile"),
        "report_kind" => @snapshot["report_kind"],
        "participation" => @snapshot["participation"]&.slice("invited", "started", "completed", "completion_rate"),
        "signals" => Array(@snapshot["signals"]).first(10).map { |s| s.slice("label", "strength", "departments", "signal_type", "evidence_count") },
        "patterns" => Array(@snapshot["patterns"]).first(8).map { |p| p.slice("title", "description", "confidence", "departments", "linked_signal_labels") },
        "recommendations" => Array(@snapshot["recommendations"]).map { |r| r.slice("title", "description", "priority", "impact_score", "feasibility_score") },
        "client_stack" => Array(@snapshot["client_stack"]).map { |s| s["name"] }.compact,
        "owned_solutions" => Array(@snapshot["owned_solutions"]).map { |s| s.slice("name", "description", "addresses_signals") },
        "document_count" => Array(@snapshot["supporting_documents"]).size
      }
    end

    def normalize(parsed)
      return nil unless parsed.is_a?(Hash)

      governing = parsed["governing_thought"].to_s.strip
      summary = parsed["executive_summary"].to_s.strip
      return nil if governing.blank? && summary.blank?

      {
        "governing_thought" => governing.presence,
        "executive_summary" => summary.presence,
        "supporting_points" => Array(parsed["supporting_points"]).map { |p| p.to_s.strip }.reject(&:blank?).first(4),
        "stakes" => parsed["stakes"].to_s.strip.presence,
        "implications" => Array(parsed["implications"]).filter_map do |item|
          next unless item.is_a?(Hash)

          title = item["pattern_title"].to_s.strip
          statement = item["statement"].to_s.strip
          next if statement.blank?

          { "pattern_title" => title, "statement" => statement }
        end,
        "roadmap" => normalize_roadmap(parsed["roadmap"]),
        "generated_by" => "llm"
      }
    end

    def normalize_roadmap(roadmap)
      return nil unless roadmap.is_a?(Hash)

      phases = %w[now next later].to_h do |phase|
        items = Array(roadmap[phase]).filter_map do |item|
          next unless item.is_a?(Hash)

          title = item["title"].to_s.strip
          next if title.blank?

          { "title" => title, "rationale" => item["rationale"].to_s.strip.presence }
        end
        [phase, items.first(5)]
      end
      phases.values.any?(&:any?) ? phases : nil
    end
  end
end
