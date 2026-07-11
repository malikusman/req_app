# frozen_string_literal: true

module EmployeeValue
  class GenerateDigestService
    def self.call(employee:, period_key: nil)
      new(employee: employee, period_key: period_key).call
    end

    def initialize(employee:, period_key: nil)
      @employee = employee
      @company = employee.company
      @period_key = period_key.presence || default_period_key
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
        status: "draft",
        content: content,
        source_refs: source_refs,
        model_version: "employee-value-v1",
        prompt_version: "rules-v1",
        generated_at: Time.current,
        delivery_status: nil
      )
      digest.save!
      digest
    end

    private

    def default_period_key
      Time.current.utc.strftime("%Y-%m")
    end

    def build_content
      insights = @employee.conversation_insights.order(created_at: :desc).limit(20)
      catalog_matches = relevant_catalog_matches

      insight_items = insights.map do |insight|
        {
          "id" => insight.id,
          "type" => insight.insight_type,
          "summary" => insight.summary.to_s.truncate(240),
          "conversation_id" => insight.conversation_id
        }
      end

      match_items = catalog_matches.map do |match|
        entry = match.solution_catalog_entry
        {
          "match_id" => match.id,
          "name" => entry.name,
          "vendor" => entry.vendor,
          "why_it_fits" => match.why_it_fits,
          "score" => match.score
        }
      end

      source_refs = insight_items.map { |i| { "type" => "conversation_insight", "id" => i["id"] } } +
                   match_items.map { |m| { "type" => "company_catalog_match", "id" => m["match_id"] } }

      {
        "employee_id" => @employee.id,
        "period_key" => @period_key,
        "headline" => "Your personal workflow insights",
        "intro" => "Private summary based only on your conversations and approved catalog matches for your role.",
        "insights" => insight_items,
        "suggested_tools" => match_items,
        "privacy_note" => "This digest never includes other employees' data.",
        "_source_refs" => source_refs
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
        .limit(20)
        .select do |match|
          entry = match.solution_catalog_entry
          next false unless entry&.active?

          departments = Array(entry.try(:departments)).map(&:downcase)
          roles = Array(entry.try(:role_relevance)).map(&:downcase)
          dept_ok = departments.blank? || dept.blank? || departments.include?(dept)
          role_ok = roles.blank? || role.blank? || roles.any? { |r| role.include?(r) }
          dept_ok && role_ok
        end
        .first(5)
    end
  end
end
