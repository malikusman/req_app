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
    def self.call(company:, snapshot:, role_notes: [])
      new(company: company, snapshot: snapshot, role_notes: role_notes).call
    end

    # role_notes: what each role's people said they would do with more time
    # (Findings::ForReport#role_potential_notes). Given to the writer only, so it can
    # write one line about the role; never stored in the snapshot.
    def initialize(company:, snapshot:, role_notes: [])
      @company = company
      @snapshot = snapshot
      @role_notes = Array(role_notes)
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
        "document_count" => @snapshot.dig("evidence_base", "documents").to_i,
        # Role by role, with hours already computed. The only hour figures the
        # writer may quote are these, as given.
        "findings" => findings_context,
        "role_potential_notes" => @role_notes
      }
    end

    def findings_context
      view = @snapshot["findings"]
      return nil unless view.is_a?(Hash) && view.dig("totals", "findings").to_i.positive?

      {
        "totals" => view["totals"],
        "departments" => Array(view["departments"]).map do |d|
          {
            "name" => d["name"], "hours" => hours_text(d["hours_min"], d["hours_max"]),
            "roles" => d["roles"].map do |r|
              {
                "role" => r["title"], "people" => r["people"], "hours" => hours_text(r["hours_min"], r["hours_max"]),
                "findings" => r["findings"].map do |f|
                  { "task" => f["title"], "what_snags" => f["friction"], "how_often" => f["frequency"],
                    "how_long" => f["duration"], "waiting" => f["effort_type"] == "waiting",
                    "hours" => hours_text(f["hours_min"], f["hours_max"]) }
                end
              }
            end
          }
        end
      }
    end

    # "1,050–1,200 hours a year" — the exact form the prose may repeat.
    def hours_text(min, max)
      return nil if min.nil?

      fmt = ->(n) { ActiveSupport::NumberHelper.number_to_delimited(n) }
      "#{min == max ? fmt.call(min) : "#{fmt.call(min)}–#{fmt.call(max)}"} hours a year"
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
      # Sentence by sentence: one stray figure in a five-sentence summary used to
      # blank the whole summary. A summary left with fewer than two sentences is
      # dropped, and the page falls back to the computed one.
      kept = summary.split(/(?<=[.!?])\s+/).select { |sentence| text_numbers_grounded?(sentence, allowed) }
      summary = kept.size >= 2 ? kept.join(" ") : ""

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
        "role_potential" => normalize_role_potential(parsed["role_potential"]),
        "generated_by" => "llm"
      }
    end

    # The number guardrail now lives in Llm::GroundedNumbers so the discovery
    # package uses the same one rather than a second implementation.
    # Everything the writer was actually GIVEN, not just key_metrics.
    #
    # The old set read key_metrics alone, which made the guard strict in the wrong
    # place: a figure the model correctly lifted from a pattern description or a
    # recommendation was treated as invented. Widening the source is what makes it
    # safe to also catch bare quantities like "14 hours a week" — otherwise
    # tightening the pattern would start deleting correct sentences.
    #
    # Metric headlines are truncated to 24 chars by MetricExtractor, so a unit can
    # be cut off ("11-14 business da..."). Reading the full context recovers those
    # numbers from the surrounding label and source text.
    def grounded_number_set
      Llm::GroundedNumbers.allowed_numbers(evidence_number_sources)
    end

    def evidence_number_sources
      context = evidence_context
      [
        Array(context["key_metrics"]).flat_map { |m| [m["headline"], m["comparison"], m["label"], m["source"]] },
        Array(context["signals"]).map { |s| s["label"] },
        Array(context["patterns"]).flat_map { |p| [p["title"], p["description"]] },
        Array(context["recommendations"]).flat_map { |r| [r["title"], r["description"]] },
        Array(@snapshot["implications"]).map { |i| i["statement"] },
        @snapshot.dig("situation", "context"),
        findings_number_sources
      ].flatten.compact
    end

    # Every hour figure in the findings, in the forms prose writes them: the range,
    # and each end of it, with and without thousands separators.
    def findings_number_sources
      view = @snapshot["findings"]
      return [] unless view.is_a?(Hash)

      rows = [view["totals"]] + Array(view["departments"]).flat_map do |d|
        [d] + d["roles"] + d["roles"].flat_map { |r| r["findings"] }
      end
      rows.compact.flat_map do |row|
        min, max = row["hours_min"], row["hours_max"]
        next [] if min.nil?

        [min, max].flat_map { |n| ["#{n} hours", "#{ActiveSupport::NumberHelper.number_to_delimited(n)} hours"] } +
          ["#{min}-#{max} hours", hours_text(min, max)]
      end
    end

    def text_numbers_grounded?(text, allowed)
      Llm::GroundedNumbers.grounded?(text, allowed)
    end

    # One line per role, about the role. No figures at all — it is written from what
    # people hoped to do, which carries no measurement — and only for roles the
    # writer was actually given notes for.
    def normalize_role_potential(items)
      known = @role_notes.to_h { |n| [[n["department"].to_s.downcase, n["role"].to_s.downcase], n] }
      Array(items).filter_map do |item|
        next unless item.is_a?(Hash)

        note = known[[item["department"].to_s.downcase, item["role"].to_s.downcase]]
        statement = item["statement"].to_s.strip
        next if note.nil? || statement.blank? || statement.length > 240 || statement.match?(/\d/)

        { "department" => note["department"], "role" => note["role"], "statement" => statement }
      end
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
