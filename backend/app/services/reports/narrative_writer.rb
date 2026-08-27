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
        # Real, cited business numbers — the ONLY numbers the writer may quote.
        "key_metrics" => Array(@snapshot["key_metrics"]).map { |m| m.slice("headline", "label", "comparison", "source") },
        # Strength/confidence are passed as plain bands, never as raw floats, so
        # the model can't parrot "a signal strength of 0.74" into client prose.
        "signals" => Array(@snapshot["signals"]).first(10).map do |s|
          { "label" => s["label"], "strength" => band(s["strength"]), "departments" => s["departments"],
            "signal_type" => s["signal_type"], "evidence_count" => s["evidence_count"] }
        end,
        "patterns" => Array(@snapshot["patterns"]).first(8).map do |p|
          { "title" => p["title"], "description" => p["description"], "confidence" => band(p["confidence"]),
            "departments" => p["departments"], "linked_signal_labels" => p["linked_signal_labels"] }
        end,
        "recommendations" => Array(@snapshot["recommendations"]).map { |r| r.slice("title", "description", "priority") },
        "client_stack" => Array(@snapshot["client_stack"]).map { |s| s["name"] }.compact,
        "document_count" => Array(@snapshot["supporting_documents"]).size
      }
    end

    # 0..1 (or 0..100) score → plain band. Keeps internal numbers out of the
    # LLM's raw material entirely.
    def band(value)
      v = value.to_f
      v /= 100.0 if v > 1.0
      if v >= 0.66 then "high"
      elsif v >= 0.4 then "medium"
      else "low"
      end
    end

    def normalize(parsed)
      return nil unless parsed.is_a?(Hash)

      governing = parsed["governing_thought"].to_s.strip
      summary = parsed["executive_summary"].to_s.strip
      return nil if governing.blank? && summary.blank?

      # Guardrail: the model is told to cite only real key_metrics numbers, but
      # nothing enforced it. Drop any prose carrying a "significant" figure
      # (currency, %, decimal, thousands, or a range) that isn't grounded in the
      # evidence — the headline falls back to the deterministic grounded prose
      # rather than shipping a fabricated statistic to the client.
      allowed = grounded_number_set
      governing = "" unless text_numbers_grounded?(governing, allowed)
      summary = "" unless text_numbers_grounded?(summary, allowed)

      {
        "governing_thought" => governing.presence,
        "executive_summary" => summary.presence,
        "supporting_points" => Array(parsed["supporting_points"]).map { |p| p.to_s.strip }
          .reject(&:blank?).select { |p| text_numbers_grounded?(p, allowed) }.first(4),
        "stakes" => parsed["stakes"].to_s.strip.presence&.then { |s| text_numbers_grounded?(s, allowed) ? s : nil },
        "implications" => Array(parsed["implications"]).filter_map do |item|
          next unless item.is_a?(Hash)

          title = item["pattern_title"].to_s.strip
          statement = item["statement"].to_s.strip
          next if statement.blank?
          next unless text_numbers_grounded?(statement, allowed)

          { "pattern_title" => title, "statement" => statement }
        end,
        "roadmap" => normalize_roadmap(parsed["roadmap"]),
        "generated_by" => "llm"
      }
    end

    # The number guardrail now lives in Llm::GroundedNumbers so the discovery
    # package uses the same one rather than a second implementation.
    def grounded_number_set
      Llm::GroundedNumbers.allowed_numbers(
        Array(@snapshot["key_metrics"]).flat_map { |m| [m["headline"], m["comparison"]] }
      )
    end

    def text_numbers_grounded?(text, allowed)
      Llm::GroundedNumbers.grounded?(text, allowed)
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
