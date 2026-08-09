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
          priority: priority_for(primary.strength),
          catalog_matches: catalog,
          related_signal_ids: signals.pluck(:id),
          related_pattern_ids: [pattern.id]
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
          priority: priority_for(signal.strength),
          catalog_matches: catalog,
          related_signal_ids: [signal.id],
          related_pattern_ids: []
        }
      end

      recommendations.uniq { |r| r[:title] }
    end

    # Differentiated priority aligned with the report's High/Medium/Low bands, so
    # recommendations no longer all read "MEDIUM" (the old 0.8 gate was
    # unreachable under the corrected strength curve).
    def priority_for(strength)
      s = strength.to_f
      if s >= 0.66 then "high"
      elsif s >= 0.45 then "medium"
      else "low"
      end
    end
  end
end
