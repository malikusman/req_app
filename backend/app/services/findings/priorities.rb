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

    def self.call(company:, view:)
      new(company: company, view: view).call
    end

    def initialize(company:, view:)
      @company = company
      @findings = Array(view&.dig("departments")).flat_map do |department|
        department["roles"].flat_map { |role| role["findings"] }
      end
      @by_id = @findings.index_by { |f| f["id"] }
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
      end.first(MAX)
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
