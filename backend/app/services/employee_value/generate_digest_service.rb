# frozen_string_literal: true

module EmployeeValue
  class GenerateDigestService
    INTEREST_ALIASES = {
      "approvals" => %w[approval bottleneck workflow],
      "automation" => %w[manual automation process spreadsheet],
      "integrations" => %w[integration sap excel tool dependency],
      "reporting" => %w[report data silo reconciliation],
      "ai tools" => %w[ai tool catalog recommendation]
    }.freeze

    def self.call(employee:, period_key: nil)
      new(employee: employee, period_key: period_key).call
    end

    def initialize(employee:, period_key: nil)
      @employee = employee
      @company = employee.company
      @period_key = period_key.presence || default_period_key
      @preference = EmployeeValuePreference.find_by(employee_id: employee.id)
    end

    def call
      content = build_content
      source_refs = content.delete("_source_refs") || []

      digest = EmployeeValueDigest.find_or_initialize_by(
        employee: @employee,
        period_key: @period_key
      )
      digest.assign_attributes(
        company: @company,
        status: digest.status == "sent" ? digest.status : "draft",
        content: content,
        source_refs: source_refs,
        model_version: "employee-value-v2",
        prompt_version: "rules-v2-interests",
        generated_at: Time.current,
        delivery_status: digest.delivery_status
      )
      digest.save!
      digest
    end

    private

    def default_period_key
      Time.current.utc.strftime("%Y-%m")
    end

    def interests
      Array(@preference&.interests).map { |i| i.to_s.strip.downcase }.reject(&:blank?).uniq
    end

    def build_content
      insight_rows = personal_insights
      match_items = relevant_catalog_matches
      tips = build_tips(insight_rows, match_items)
      team_theme = anonymized_team_theme
      heard = insight_rows.map { |i| i["summary"] }.first(5)
      heard = ["Your recent interview captured day-to-day workflow friction we can help with."] if heard.empty?

      source_refs =
        insight_rows.map { |i| { "type" => "conversation_insight", "id" => i["id"] } } +
        match_items.map { |m| { "type" => "company_catalog_match", "id" => m["match_id"] } } +
        Array(team_theme["_pattern_ids"]).map { |id| { "type" => "pattern", "id" => id } }

      name = @employee.display_name.presence || "there"
      role = [@employee.role_title, @employee.department].compact.join(" · ")

      {
        "employee_id" => @employee.id,
        "period_key" => @period_key,
        "headline" => "Your personal workflow insights",
        "greeting" => "Hi #{name} — here is a private digest for #{role.presence || "your role"}.",
        "intro" => intro_copy,
        "heard" => heard,
        "insights" => insight_rows,
        "tips" => tips,
        "tools" => match_items.map { |m| { "name" => m["name"], "why" => m["why_it_fits"], "vendor" => m["vendor"] } },
        "suggested_tools" => match_items,
        "team_theme" => team_theme["text"],
        "interests_used" => interests,
        "privacy_note" => "This digest is private to you. It never includes other employees' identifiable answers.",
        "_source_refs" => source_refs
      }
    end

    def intro_copy
      if interests.any?
        "Based on your interview and your interests (#{interests.join(', ')}), plus approved company catalog matches."
      else
        "Private summary based on your conversations and approved catalog matches for your role."
      end
    end

    def personal_insights
      rows = @employee.conversation_insights.order(created_at: :desc).limit(30).map do |insight|
        {
          "id" => insight.id,
          "type" => insight.insight_type,
          "summary" => insight.summary.to_s.truncate(240),
          "conversation_id" => insight.conversation_id,
          "score" => interest_score("#{insight.insight_type} #{insight.summary}")
        }
      end

      ranked = rows.sort_by { |r| [-r["score"], -r["id"].to_i] }
      ranked = ranked.first(8)
      ranked.each { |r| r.delete("score") }
      ranked
    end

    def build_tips(insights, matches)
      tips = []
      if insights.any?
        tips << "Revisit the top friction from your interview and note where handoffs wait longest."
      end
      if matches.any?
        tips << "Try one suggested capability below on a single recurring task before wider rollout."
      end
      if interests.include?("approvals") || insights.any? { |i| i["summary"].to_s.downcase.include?("approv") }
        tips << "Document your approval path (who, SLA, fallback) so bottlenecks are visible to leads."
      end
      if interests.include?("automation") || interests.include?("integrations")
        tips << "List the systems you re-enter data between — those seams are prime automation candidates."
      end
      tips << "Share one concrete example with your admin if a clarification request arrives." if tips.size < 2
      tips.first(4)
    end

    def anonymized_team_theme
      patterns = @company.patterns.order(confidence: :desc).limit(3)
      return { "text" => nil, "_pattern_ids" => [] } if patterns.empty?

      titles = patterns.map(&:title)
      {
        "text" => "Across the company, emerging themes include: #{titles.join('; ')}. Your digest stays personal — this is aggregate context only.",
        "_pattern_ids" => patterns.map(&:id)
      }
    end

    def relevant_catalog_matches
      dept = @employee.department.to_s.downcase
      role = @employee.role_title.to_s.downcase

      CompanyCatalogMatch
        .where(company: @company)
        .includes(:solution_catalog_entry)
        .where("score >= ?", 0.3)
        .order(score: :desc)
        .limit(30)
        .map do |match|
          entry = match.solution_catalog_entry
          next unless entry&.active?

          departments = Array(entry.try(:departments)).map(&:downcase)
          roles = Array(entry.try(:role_relevance)).map(&:downcase)
          dept_ok = departments.blank? || dept.blank? || departments.include?(dept)
          role_ok = roles.blank? || role.blank? || roles.any? { |r| role.include?(r) }
          next unless dept_ok && role_ok

          blob = [entry.name, entry.vendor, entry.category, entry.description, match.why_it_fits].join(" ")
          {
            "match_id" => match.id,
            "name" => entry.name,
            "vendor" => entry.vendor,
            "why_it_fits" => match.why_it_fits,
            "score" => match.score.to_f + (interest_score(blob) * 0.2)
          }
        end
        .compact
        .sort_by { |m| -m["score"].to_f }
        .first(5)
        .each { |m| m["score"] = m["score"].to_f.round(2) }
    end

    def interest_score(text)
      return 0.0 if interests.empty?

      hay = text.to_s.downcase
      interests.sum do |interest|
        tokens = INTEREST_ALIASES[interest] || interest.split(/\s+/)
        tokens.any? { |t| hay.include?(t) } ? 1.0 : 0.0
      end
    end
  end
end
