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
      invited = @company.invited_count
      started = @company.employees.where(participation_status: %w[started completed]).count
      completed = @company.employees.where(participation_status: "completed").count

      dept_targets = @company.merged_settings.fetch("department_targets", {})
      custom_depts = @company.merged_settings.fetch("custom_departments", [])
      departments = (@company.employees.distinct.pluck(:department).compact + custom_depts).uniq

      {
        "participation" => {
          "invited" => invited,
          "started" => started,
          "completed" => completed,
          "completion_rate" => invited.positive? ? (completed.to_f / invited).round(2) : 0
        },
        "department_coverage" => departments.map do |dept|
          done = @company.employees.where(department: dept, participation_status: "completed").count
          target = dept_targets[dept].to_i
          target = 3 if target.zero?
          { "department" => dept, "completed" => done, "target" => target }
        end,
        "onboarding_complete" => @company.onboarding_complete?,
        "security" => {
          "unrecognized_attempts_7d" => @company.security_snapshot["unrecognized_verification_attempts_7d"].to_i,
          "last_code_rotation_at" => @company.pin_rotated_at
        },
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
