# frozen_string_literal: true

module Intelligence
  class AgenticIdeaSynthesizer
    MAX_IDEAS = 6

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      ideas = []
      signals = @company.company_signals.order(strength: :desc).limit(8)
      patterns = @company.patterns.order(confidence: :desc).limit(5)
      stack = defined?(CompanySystem) && CompanySystem.table_exists? ? @company.company_systems.active.limit(12).to_a : []
      catalog = SolutionCatalogEntry.where(active: true, category: %w[ai_agent automation]).limit(12)

      signals.each do |signal|
        break if ideas.size >= MAX_IDEAS

        pattern = patterns.find { |p| Array(p.linked_signal_ids).map(&:to_i).include?(signal.id) }
        entry = catalog.find { |c| Array(c.match_keywords).any? { |k| signal.label.to_s.downcase.include?(k.to_s.downcase) } } ||
                catalog.first
        ideas << build_idea(signal: signal, pattern: pattern, stack: stack, entry: entry)
      end

      patterns.each do |pattern|
        break if ideas.size >= MAX_IDEAS
        next if ideas.any? { |i| Array(i[:related_pattern_ids]).include?(pattern.id) }

        ideas << build_from_pattern(pattern: pattern, stack: stack, catalog: catalog)
      end

      ideas.first(MAX_IDEAS)
    end

    private

    def build_idea(signal:, pattern:, stack:, entry:)
      stack_names = stack.map(&:name)
      title = agentic_title(signal)
      {
        title: title,
        summary: "An agentic workflow that monitors \"#{signal.label}\" and assists teams before work stalls.",
        system_fit: system_fit_text(stack_names, entry),
        value_time: "Reduce wait time and re-keying around #{signal.label.downcase} by drafting the next action for a human to approve.",
        value_efficiency: "Cut repetitive handoffs between #{Array(signal.departments).presence&.join(' and ') || 'teams'} by consolidating checks in one assistive flow.",
        value_cost: "Lower exception-handling cost by catching incomplete or delayed items earlier in the process.",
        approx_timeline: signal.strength.to_f >= 0.75 ? "4–8 weeks" : "6–12 weeks",
        estimated_cost: nil,
        confidence: [[signal.strength.to_f, 0.45].max, 0.9].min,
        source: "generated",
        status: "draft",
        related_signal_ids: [signal.id],
        related_pattern_ids: pattern ? [pattern.id] : [],
        related_stack_ids: stack.first(5).map(&:id),
        solution_catalog_entry_id: entry&.id
      }
    end

    def build_from_pattern(pattern:, stack:, catalog:)
      entry = catalog.first
      stack_names = stack.map(&:name)
      {
        title: "Agent assist for #{pattern.title}",
        summary: "A guided agent that operationalizes the pattern \"#{pattern.title}\" with checklists, alerts, and draft actions.",
        system_fit: system_fit_text(stack_names, entry),
        value_time: "Compress cycle time on the workstreams tied to this pattern.",
        value_efficiency: "Standardize how exceptions are triaged across #{Array(pattern.departments).presence&.join(', ') || 'affected teams'}.",
        value_cost: "Reduce rework and overtime spent on recurring exceptions.",
        approx_timeline: "1 quarter",
        estimated_cost: nil,
        confidence: [[pattern.confidence.to_f, 0.4].max, 0.85].min,
        source: "generated",
        status: "draft",
        related_signal_ids: Array(pattern.linked_signal_ids).map(&:to_i).first(5),
        related_pattern_ids: [pattern.id],
        related_stack_ids: stack.first(5).map(&:id),
        solution_catalog_entry_id: entry&.id
      }
    end

    def agentic_title(signal)
      case signal.signal_type
      when "manual_process" then "Agentic capture for #{signal.label}"
      when "approval_bottleneck" then "Approval copilot for #{signal.label}"
      when "data_silo" then "Reconciliation agent for #{signal.label}"
      when "tool_dependency" then "Integration agent around #{signal.label}"
      else "Workflow agent for #{signal.label}"
      end.truncate(80)
    end

    def system_fit_text(stack_names, entry)
      if stack_names.any?
        base = "Designed to sit alongside #{stack_names.first(4).join(', ')}"
        entry ? "#{base}, optionally leveraging #{entry.name}." : "#{base}."
      elsif entry
        "Can be introduced as a lightweight layer that feeds #{entry.name} / adjacent systems once integrations are confirmed."
      else
        "Fits as a human-in-the-loop agent on top of current spreadsheets and messaging channels, then connects to core systems."
      end
    end
  end
end
