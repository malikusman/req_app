# frozen_string_literal: true

module Intelligence
  # LLM-backed generator of tailored agentic-AI opportunity concepts, grounded in
  # the company's real signals/patterns/stack. Returns ideas in the shape
  # AgenticIdeaUpsertService expects, or nil so the caller falls back to the
  # deterministic rule-based synthesizer. Only calls the model when configured, so
  # a prod instance without a key never fabricates — it uses the rule-based path.
  class AgenticIdeaWriter
    MAX_IDEAS = 6

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      return nil unless enabled?

      client = Openai::Client.new
      return nil unless client.configured?

      @signals = @company.company_signals.order(strength: :desc).limit(12).to_a
      @patterns = @company.patterns.order(confidence: :desc).limit(8).to_a
      @stack = stack_rows
      return nil if @signals.empty? && @patterns.empty?

      parsed = client.agentic_ideas(context: evidence_context, language: @company.locale.presence || "en")
      map_ideas(parsed)
    rescue StandardError => e
      Rails.logger.warn("[Intelligence::AgenticIdeaWriter] falling back to rule-based: #{e.class}: #{e.message}")
      nil
    end

    private

    def enabled?
      ENV.fetch("AI_AGENTIC_IDEAS", "true").to_s.downcase != "false"
    end

    def stack_rows
      return [] unless defined?(CompanySystem) && CompanySystem.table_exists?

      @company.company_systems.active.limit(15).to_a
    end

    def evidence_context
      {
        "company" => { "name" => @company.display_name || @company.name, "profile" => @company.company_profile.slice("industry", "size_band") },
        "signals" => @signals.map { |s| { "label" => s.label, "strength" => s.strength, "departments" => s.departments, "signal_type" => s.signal_type } },
        "patterns" => @patterns.map { |p| { "title" => p.title, "description" => p.description, "departments" => p.departments } },
        "current_stack" => @stack.map(&:name).compact
      }
    end

    def map_ideas(parsed)
      ideas = parsed.is_a?(Hash) ? Array(parsed["ideas"]) : []
      return nil if ideas.empty?

      signals_by_label = @signals.index_by { |s| s.label.to_s.downcase }
      catalog = SolutionCatalogEntry.where(active: true, category: %w[ai_agent automation]).limit(20).to_a

      mapped = ideas.filter_map do |idea|
        title = idea["title"].to_s.strip
        next if title.blank?

        addressed = Array(idea["addresses_signals"]).filter_map { |l| signals_by_label[l.to_s.downcase] }
        entry = catalog.find { |c| Array(c.match_keywords).any? { |k| title.downcase.include?(k.to_s.downcase) } }
        confidence = idea["confidence"].to_f
        confidence = 0.6 unless confidence.positive?

        {
          title: title,
          summary: idea["summary"].to_s.strip.presence,
          system_fit: idea["system_fit"].to_s.strip.presence,
          value_time: idea["value_time"].to_s.strip.presence,
          value_efficiency: idea["value_efficiency"].to_s.strip.presence,
          value_cost: idea["value_cost"].to_s.strip.presence,
          approx_timeline: idea["approx_timeline"].to_s.strip.presence || effort_timeline(idea["effort"]),
          estimated_cost: nil,
          confidence: confidence.clamp(0.0, 0.95).round(2),
          source: "generated",
          status: "draft",
          related_signal_ids: addressed.map(&:id),
          related_pattern_ids: [],
          related_stack_ids: @stack.first(5).map(&:id),
          solution_catalog_entry_id: entry&.id
        }
      end.first(MAX_IDEAS)

      mapped.presence
    end

    def effort_timeline(effort)
      case effort.to_s.upcase
      when "S" then "2–4 weeks"
      when "L" then "3–6 months"
      else "6–12 weeks"
      end
    end
  end
end
