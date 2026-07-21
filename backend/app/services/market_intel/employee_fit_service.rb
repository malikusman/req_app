# frozen_string_literal: true

module MarketIntel
  class EmployeeFitService
    MIN_SCORE = ENV.fetch("AI_MARKET_ALERT_MIN_SCORE", "0.8").to_f

    def self.call(employee:, candidate:)
      new(employee: employee, candidate: candidate).call
    end

    def initialize(employee:, candidate:)
      @employee = employee
      @candidate = candidate
      @preference = employee.employee_value_preference
    end

    def call
      score, rationale = score_with_rationale
      {
        fit_score: score.round(3),
        fit_rationale: rationale,
        qualifies: score >= MIN_SCORE && !@candidate.stub? && @candidate.analysis_status == "analyzed"
      }
    end

    private

    def score_with_rationale
      reasons = []
      score = 0.15 # base curiosity for opted-in AI interest path

      blob = candidate_blob
      dept = @employee.department.to_s.downcase
      role = @employee.role_title.to_s.downcase
      tools = Array(@employee.profile_data["primary_tools"]).map { |t| t.to_s.downcase }
      interests = Array(@preference&.interests).map { |i| i.to_s.downcase }

      if dept.present? && blob.include?(dept)
        score += 0.25
        reasons << "matches your #{@employee.department} department"
      end

      if role.present? && role.split.any? { |token| token.length > 3 && blob.include?(token) }
        score += 0.15
        reasons << "relevant to your role (#{@employee.role_title})"
      end

      tool_hits = tools.select { |t| t.length > 2 && blob.include?(t) }
      if tool_hits.any?
        score += [0.1 * tool_hits.size, 0.25].min
        reasons << "relates to tools you use (#{tool_hits.first(3).join(', ')})"
      end

      interest_hits = interests.select { |i| blob.include?(i) || interest_aliases(i).any? { |a| blob.include?(a) } }
      if interest_hits.any?
        score += 0.2
        reasons << "aligns with your interests (#{interest_hits.join(', ')})"
      elsif interests.include?("ai tools") || interests.include?("automation")
        score += 0.1
        reasons << "you opted into AI / automation updates"
      end

      insight_hits = recent_insight_terms.count { |term| blob.include?(term) }
      if insight_hits.positive?
        score += [0.05 * insight_hits, 0.2].min
        reasons << "connects to themes from your discovery interview"
      end

      if Array(@candidate.industries).map(&:downcase).include?("general") == false &&
         Array(@candidate.industries).any? { |ind| dept.include?(ind.to_s.downcase) || blob.include?(dept) }
        score += 0.05
      end

      score = [[score, 1.0].min, 0.0].max
      rationale = if reasons.any?
                    "We know you work as #{@employee.role_title.presence || 'a team member'}" \
                      "#{dept.present? ? " in #{@employee.department}" : ""}. " \
                      "This #{@candidate.entity_type} fits because #{reasons.to_sentence}."
                  else
                    "General AI market item with limited overlap to your profile."
                  end
      [score, rationale]
    end

    def candidate_blob
      [
        @candidate.name,
        @candidate.description,
        @candidate.summary,
        @candidate.vendor,
        Array(@candidate.topics).join(" "),
        Array(@candidate.industries).join(" ")
      ].compact.join(" ").downcase
    end

    def interest_aliases(interest)
      {
        "approvals" => %w[approval bottleneck workflow],
        "automation" => %w[manual automation process spreadsheet],
        "integrations" => %w[integration sap excel tool],
        "reporting" => %w[report data reconciliation],
        "ai tools" => %w[ai tool llm copilot model]
      }[interest] || []
    end

    def recent_insight_terms
      @employee.conversation_insights.order(created_at: :desc).limit(10).flat_map do |insight|
        words = "#{insight.summary} #{Array(insight.structured_data&.dig('topics')).join(' ')}"
                .downcase.scan(/[a-z]{4,}/)
        words.first(12)
      end.uniq
    end
  end
end
