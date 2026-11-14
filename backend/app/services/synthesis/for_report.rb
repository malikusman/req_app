# frozen_string_literal: true

module Synthesis
  # What the Diagnostic Report takes from synthesis (Doc 15 §4.4, §4.5, §8,
  # §14.1) — only what a consultant approved (Doc 00 C11), because the report
  # snapshot is served to the company as well as rendered.
  #
  #   - The operating picture, for "How the business runs today", once approved.
  #   - Opportunities above any one task, for a consolidated subsection inside
  #     the findings — never a section of its own, and only when there are some
  #     (Doc 00 C7).
  #   - Opportunities not recommended, for "What we are not recommending" (C14).
  #   - Root causes, worded as analysis (§8.2).
  #   - Where leadership's view and staff evidence differ materially, worded as
  #     a difference to validate, never as fact (§8.4) — attributed to
  #     management, never to a person.
  #
  # Leadership's own words reach the report only as these approved, diplomatic
  # lines; nothing consultant-private ever does.
  class ForReport
    ABOVE_TASK = %w[PROCESS DEPARTMENT CROSS_DEPARTMENT COMPANY_WIDE].freeze

    def self.call(company) = new(company).call

    def initialize(company)
      @company = company
      @engagement = company.current_engagement
    end

    def call
      return {} unless @engagement

      run = SynthesisRun.latest_finished(@engagement)
      opportunities = ConsultancyOpportunity.current.approved.where(engagement: @engagement).order(:id).to_a
      out = {
        "synthesis_version" => run&.version,
        "operating_picture" => operating_picture(run),
        "opportunities" => opportunities.select { |o| ABOVE_TASK.include?(o.level) && o.recommended_next_action != "NOT_RECOMMENDED" }
                                        .map { |o| opportunity_json(o) },
        "not_recommended" => opportunities.select { |o| o.recommended_next_action == "NOT_RECOMMENDED" }.map do |o|
          { "title" => o.title, "why" => [o.problem_statement, o.priority_reason].compact.join(" ") }
        end,
        "root_causes" => RootCause.current.approved.where(engagement: @engagement).order(:id).map do |r|
          { "statement" => r.statement, "departments" => r.affected_departments, "fact_status" => r.fact_status }
        end,
        "management_views" => ManagementValidation.current.approved.where(engagement: @engagement, material: true)
                                                  .order(:id).map { |v| management_view(v) }
      }
      out.values_at("operating_picture", "opportunities", "not_recommended", "root_causes", "management_views")
         .any?(&:present?) ? out : {}
    end

    private

    def operating_picture(run)
      return nil unless run&.operating_picture_status == "APPROVED"

      picture = run.display_operating_picture || {}
      picture.except("evidence").presence
    end

    def opportunity_json(o)
      {
        "title" => o.title, "level" => o.level, "category" => o.category, "problem_statement" => o.problem_statement,
        "direction" => o.intervention_direction, "capacity" => o.capacity_reference,
        "departments" => o.affected_departments, "next_step" => o.recommended_next_action,
        "planned_change" => o.planned_initiative_conflict
      }
    end

    # Doc 15 §8.4: the difference described, diplomatically, with validation
    # recommended — or the consultant's own conclusion where they reached one.
    def management_view(validation)
      {
        "management_reports" => validation.management_view,
        "staff_describe" => validation.what_evidence_shows,
        "relationship" => validation.relationship,
        "conclusion" => validation.status == "RESOLVED" ? validation.resolution : nil,
        "fact_status" => validation.fact_status
      }
    end
  end
end
