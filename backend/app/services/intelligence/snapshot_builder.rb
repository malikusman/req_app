# frozen_string_literal: true

module Intelligence
  class SnapshotBuilder
    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      participation = @company.participation
      invited, started, completed = participation.values_at("invited", "started", "completed")

      dept_targets = @company.merged_settings.fetch("department_targets", {})
      custom_depts = @company.merged_settings.fetch("custom_departments", [])
      # The departments the client planned to take part come first (Doc 07 §7, P1),
      # so coverage shows a planned department nobody has joined from yet.
      engagement = @company.current_engagement
      planned_depts = Array(engagement&.planned_departments).map { |d| d["name"] }
      departments = (planned_depts + @company.employees.distinct.pluck(:department).compact + custom_depts).uniq

      {
        "participation" => {
          "invited" => invited,
          "started" => started,
          "completed" => completed,
          "completion_rate" => invited.positive? ? (completed.to_f / invited).round(2) : 0
        },
        "department_coverage" => departments.map do |dept|
          done = @company.employees.where(department: dept, participation_status: "completed").count
          # How many the client planned from this department (P2), else the
          # setting, else three.
          target = engagement&.planned_count_for(dept).to_i
          target = dept_targets[dept].to_i if target.zero?
          target = 3 if target.zero?
          { "department" => dept, "completed" => done, "target" => target }
        end,
        "onboarding_complete" => @company.onboarding_complete?,
        "security" => {
          "unrecognized_attempts_7d" => @company.security_snapshot["unrecognized_verification_attempts_7d"].to_i,
          "last_code_rotation_at" => @company.pin_rotated_at
        },
        "signal_count" => @company.company_signals.count,
        "top_pain_points" => @company.company_signals.order(strength: :desc).limit(5).map do |s|
          { "id" => s.id, "label" => s.label, "strength" => s.strength, "departments" => s.departments, "signal_type" => s.signal_type }
        end,
        "emerging_patterns" => @company.patterns.order(confidence: :desc).limit(3).map do |p|
          { "id" => p.id, "title" => p.title, "confidence" => p.confidence, "departments" => p.departments }
        end,
        "report_readiness_score" => @company.report_readiness_score,
        "report_ready" => @company.report_readiness_score >= 100,
        "recommendation_count" => @company.recommendations.published.count,
        "recent_timeline" => @company.insight_timeline_events.order(occurred_at: :desc).limit(8).map do |e|
          { "type" => e.event_type, "title" => e.title, "summary" => e.summary, "occurred_at" => e.occurred_at }
        end
      }
    end
  end
end
