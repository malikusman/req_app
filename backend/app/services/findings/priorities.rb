# frozen_string_literal: true

module Findings
  # Where to act first, built from the findings rather than from keyword signals.
  #
  # A model groups the findings into a few themes — "supplier and customer data
  # re-keyed by hand" across Procurement, Sales and Finance — and says WHAT each
  # addresses. It never says how: no tools, vendors or build steps, because Stage 1
  # diagnoses and the design is Stage 2's. It writes no numbers either.
  #
  # Everything else is computed here. The model only returns finding ids; Ruby
  # checks every id is real, lets each finding sit in one theme at most, sums the
  # hours from the findings themselves, and ranks by them. So a priority's hours
  # always equal the rows it names, and the ranking cannot be talked up.
  #
  # Without a model, or if nothing it returns survives the checks, the largest
  # findings stand as their own priorities.
  class Priorities
    MAX = 5
    # Build language, in any priority's words, means the model described a
    # solution — which is Stage 2's job — so the priority is dropped.
    BUILD_WORDS = /\b(implement\w*|deploy\w*|build\w*|install\w*|integrat\w*|automat\w*|rpa|api|bot|chatbot|agent|software|platform|tool|vendor|ai)\b/i

    # The kind of change a priority calls for, in the client's words. A fixed list,
    # so Stage 1 can say "a ready-made tool" without ever naming one — product
    # names belong to Stage 2's design.
    INTERVENTIONS = {
      "process_change" => "Change how the work is done",
      "existing_system" => "Make better use of a system you already have",
      "ready_made_tool" => "A ready-made tool",
      "connect_systems" => "Connect systems that don't talk to each other",
      "automation" => "Automate a repetitive step",
      "ai_assistant" => "An AI assistant for the task",
      "standards_training" => "A clear standard, and training on it"
    }.freeze

    # Direction and "not recommended" lines may say what kind of change (so
    # "automate" is fine) but never how it is built, what it costs or how long.
    BUILD_DETAIL = /\b(implement\w*|deploy\w*|build\w*|install\w*|api|vendor\w*|licen[cs]\w*|subscription\w*|cost\w*|price\w*|budget\w*|weeks?|months?)\b/i

    NOT_RECOMMENDED_MAX = 3

    attr_reader :not_recommended

    def self.call(company:, view:)
      new(company: company, view: view).call
    end

    def initialize(company:, view:)
      @company = company
      @findings = Array(view&.dig("departments")).flat_map do |department|
        department["roles"].flat_map { |role| role["findings"] }
      end
      @by_id = @findings.index_by { |f| f["id"] }
      @not_recommended = []
    end

    def call
      return [] if @findings.empty?

      themes = themed || []
      themes = one_per_finding if themes.empty?
      rank(themes)
    end

    private

    def themed
      return nil if ENV.fetch("AI_REPORT_NARRATIVE", "true").to_s.downcase == "false"

      client = Openai::Client.new
      return nil unless client.configured?

      parsed = client.finding_priorities(context: context, language: @company.locale.presence || "en")
      @not_recommended = normalise_not_recommended(parsed)
      normalise(parsed)
    rescue StandardError => e
      Rails.logger.warn("[Findings::Priorities] using the largest findings instead: #{e.class}: #{e.message}")
      nil
    end

    def context
      goals = @company.company_profile["business_goals"]
      {
        "business_goals" => Array(goals).map(&:to_s).reject(&:blank?),
        "findings" => @findings.map do |f|
          { "id" => f["id"], "task" => f["title"], "role" => f["role"], "department" => f["department"],
            "what_snags" => f["friction"], "hours_a_year" => f["hours_max"] ? "#{f['hours_min']}-#{f['hours_max']}" : nil,
            "waiting" => f["effort_type"] == "waiting" }
        end
      }
    end

    def normalise(parsed)
      goals = Array(@company.company_profile["business_goals"]).map(&:to_s)
      used = Set.new
      Array(parsed.is_a?(Hash) ? parsed["priorities"] : nil).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s.strip
        what = item["what"].to_s.strip
        next if title.blank? || what.blank? || title.length > 100 || what.length > 400
        next if [title, what].any? { |t| t.match?(/\d/) || t.match?(BUILD_WORDS) }

        ids = Array(item["finding_ids"]).map(&:to_i).select { |id| @by_id.key?(id) && used.add?(id) }
        next if ids.empty?

        goal = item["serves_goal"].to_s.strip
        theme(title: title, what: what, ids: ids, goal: goals.find { |g| g.casecmp?(goal) })
          .merge(direction(item))
      end.first(MAX)
    end

    # The kind of change, from the fixed list, and one sentence on its direction.
    # A direction that names a product, a build step, a cost or a timescale is
    # dropped; the type alone still stands.
    def direction(item)
      type = INTERVENTIONS.key?(item["intervention_type"].to_s) ? item["intervention_type"].to_s : nil
      text = item["direction"].to_s.strip
      text = "" if text.length > 240 || text.match?(/\d/) || text.match?(BUILD_DETAIL) || names_a_product?(text)
      { "intervention_type" => type, "intervention_label" => type && INTERVENTIONS[type],
        "direction" => text.presence }
    end

    # What was considered and is not recommended, and why — tied to findings, so
    # it is about this company's work and not general advice.
    def normalise_not_recommended(parsed)
      Array(parsed.is_a?(Hash) ? parsed["not_recommended"] : nil).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s.strip
        why = item["why"].to_s.strip
        next if title.blank? || why.blank? || title.length > 120 || why.length > 300
        next if [title, why].any? { |t| t.match?(/\d/) || t.match?(BUILD_DETAIL) || names_a_product?(t) }

        ids = Array(item["finding_ids"]).map(&:to_i).select { |id| @by_id.key?(id) }
        next if ids.empty?

        { "title" => title, "why" => why, "finding_ids" => ids }
      end.first(NOT_RECOMMENDED_MAX)
    end

    def names_a_product?(text)
      @product_names ||= SolutionCatalogEntry.pluck(:name, :vendor).flatten.compact
                                             .map { |n| n.to_s.strip.downcase }.select { |n| n.length >= 3 }.uniq
      down = text.downcase
      @product_names.any? { |n| down.match?(/\b#{Regexp.escape(n)}\b/) }
    end

    def one_per_finding
      @findings.select { |f| f["hours_max"] }.sort_by { |f| -f["hours_max"] }.first(MAX).map do |f|
        theme(title: f["title"], what: f["friction"].to_s, ids: [f["id"]], goal: nil)
      end
    end

    def theme(title:, what:, ids:, goal:)
      members = ids.map { |id| @by_id[id] }
      quantified = members.select { |f| f["hours_min"] }
      {
        "title" => title,
        "what" => what,
        "serves_goal" => goal,
        "finding_ids" => ids,
        "findings" => members.map { |f| f.slice("title", "role", "department", "hours_min", "hours_max") },
        "roles" => members.map { |f| f["role"] }.compact.uniq,
        "departments" => members.map { |f| f["department"] }.compact.uniq,
        "hours_min" => quantified.any? ? quantified.sum { |f| f["hours_min"] } : nil,
        "hours_max" => quantified.any? ? quantified.sum { |f| f["hours_max"] } : nil
      }
    end

    def rank(themes)
      themes.sort_by { |t| [-t["hours_max"].to_i, -t["finding_ids"].size] }
            .each_with_index.map { |t, i| t.merge("rank" => i + 1) }
    end
  end
end
