# frozen_string_literal: true

module Intelligence
  class RecommendationSynthesizer
    RECIPES = {
      "manual_process" => {
        title: "Automate manual data entry",
        description: "Reduce spreadsheet-heavy work with workflow automation.",
        outline: "Introduce automation for repetitive data entry; consider RPA or integration platforms."
      },
      "approval_bottleneck" => {
        title: "Streamline approval workflows",
        description: "Cut wait time on sign-offs with structured approval routing.",
        outline: "Define approval SLAs, automate routing, and add visibility dashboards."
      },
      "tool_dependency" => {
        title: "Integrate core systems",
        description: "Connect ERP/CRM tools to eliminate swivel-chair work.",
        outline: "Map integration points between systems; prioritize bi-directional sync for high-volume data."
      },
      "data_silo" => {
        title: "Break down data silos",
        description: "Establish a single source of truth across teams.",
        outline: "Consolidate reporting pipelines and standardize master data."
      }
    }.freeze

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      if Companies::AgentFeatures.enabled?(@company, :opportunity_scout)
        scout_recommendations.presence || rule_based_recommendations
      else
        rule_based_recommendations
      end
    end

    private

    def scout_recommendations
      catalog = SolutionCatalogEntry.active.order(:name).limit(30).map { |item|
        { id: item.id, name: item.name, category: item.category, description: item.description }
      }
      client = Langgraph::Client.new
      thread_id = client.create_thread!
      result = client.scout_opportunities!(
        thread_id: thread_id,
        company_id: @company.id,
        solution_catalog: catalog
      )
      mapped = (result["opportunities"] || []).map { |opp| map_scout_opportunity(opp) }

      if mapped.any? { |r| requires_hitl?(r) }
        AgentInterrupt.create!(
          thread_id: thread_id,
          company: @company,
          kind: "opportunity_recommendation",
          status: "pending",
          payload: { "recommendations" => mapped, "source" => "opportunity_scout" }
        )
        return []
      end

      mapped
    rescue Langgraph::UnavailableError
      []
    end

    def map_scout_opportunity(opp)
      signal_type = infer_signal_type(opp)
      catalog = CatalogMatcher.match_opportunity(
        title: opp["title"],
        description: opp["description"],
        signal_type: signal_type
      )
      signal_ids, pattern_ids = extract_evidence_ids(opp["evidence"])

      {
        title: opp["title"],
        description: opp["description"],
        implementation_outline: [opp["benefit_summary"], opp["suggested_tools"]&.join(", ")].compact.join(" — "),
        priority: map_impact(opp["impact"]),
        catalog_matches: catalog,
        related_signal_ids: signal_ids,
        related_pattern_ids: pattern_ids,
        effort: opp["effort"],
        timeframe: opp["timeframe"],
        source: "opportunity_scout",
        evidence: opp["evidence"] || []
      }
    end

    def requires_hitl?(rec)
      rec[:priority] == "high" || rec[:evidence].blank?
    end

    def infer_signal_type(opp)
      text = "#{opp['title']} #{opp['description']}".downcase
      return "manual_process" if text.match?(/manual|spreadsheet|data entry/)
      return "approval_bottleneck" if text.match?(/approv|sign.?off|bottleneck/)
      return "tool_dependency" if text.match?(/integrat|erp|crm|system/)
      return "data_silo" if text.match?(/silo|fragment|duplicate/)

      "manual_process"
    end

    def extract_evidence_ids(evidence)
      signal_ids = []
      pattern_ids = []
      Array(evidence).each do |item|
        next unless item.is_a?(Hash)

        case item["type"].to_s
        when "signal"
          signal_ids << item["id"].to_i if item["id"].present?
        when "pattern"
          pattern_ids << item["id"].to_i if item["id"].present?
        end
      end
      [signal_ids.uniq, pattern_ids.uniq]
    end

    def map_impact(impact)
      case impact.to_s
      when "high" then "high"
      when "low" then "low"
      else "medium"
      end
    end

    def rule_based_recommendations
      recommendations = []

      @company.patterns.where(status: "confirmed").or(@company.patterns.where("confidence >= ?", 0.7)).find_each do |pattern|
        signals = @company.company_signals.where(id: pattern.linked_signal_ids)
        primary = signals.order(strength: :desc).first
        next unless primary

        recipe = RECIPES[primary.signal_type] || RECIPES["manual_process"]
        catalog = CatalogMatcher.call(signal: primary)

        outline = recipe[:outline]
        if catalog.any?
          tools = catalog.map { |c| c[:name] }.join(", ")
          outline = "#{outline} Consider: #{tools}."
        end

        recommendations << {
          title: recipe[:title],
          description: "#{recipe[:description]} (Pattern: #{pattern.title})",
          implementation_outline: outline,
          priority: primary.strength >= 0.8 ? "high" : "medium",
          catalog_matches: catalog,
          related_signal_ids: signals.pluck(:id),
          related_pattern_ids: [pattern.id],
          source: "rule_based"
        }
      end

      @company.company_signals.where("strength >= ?", 0.65).find_each do |signal|
        next if recommendations.any? { |r| r[:related_signal_ids].include?(signal.id) }

        recipe = RECIPES[signal.signal_type] || RECIPES["manual_process"]
        catalog = CatalogMatcher.call(signal: signal)
        outline = recipe[:outline]
        outline = "#{outline} Consider: #{catalog.map { |c| c[:name] }.join(', ')}." if catalog.any?

        recommendations << {
          title: recipe[:title],
          description: recipe[:description],
          implementation_outline: outline,
          priority: signal.strength >= 0.8 ? "high" : "medium",
          catalog_matches: catalog,
          related_signal_ids: [signal.id],
          related_pattern_ids: [],
          source: "rule_based"
        }
      end

      recommendations.uniq { |r| r[:title] }
    end
  end
end
