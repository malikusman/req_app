# frozen_string_literal: true

module Intelligence
  class TimelineRecorder
    def self.signal_detected!(company:, signal:)
      create!(company: company, event_type: "signal_detected", target: signal,
              title: signal.label,
              summary: "Detected in #{signal.departments.join(', ').presence || 'discovery'} (strength #{signal.strength})")
    end

    def self.signal_strengthened!(company:, signal:)
      create!(company: company, event_type: "signal_strengthened", target: signal,
              title: signal.label,
              summary: "Strength increased to #{signal.strength} across #{signal.evidence_count} mentions")
    end

    def self.pattern_detected!(company:, pattern:)
      create!(company: company, event_type: "pattern_detected", target: pattern,
              title: pattern.title,
              summary: pattern.description)
    end

    def self.interview_completed!(company:, employee:)
      create!(company: company, event_type: "interview_completed", target: employee,
              title: "#{employee.display_name || employee.phone_e164} completed discovery",
              summary: "Interview completed#{employee.department.present? ? " (#{employee.department})" : ''}")
    end

    def self.conversation_reopened!(company:, employee:, conversation:)
      addendum = conversation.state_snapshot.fetch("addendum_count", 1).to_i
      create!(company: company, event_type: "conversation_reopened", target: employee,
              title: "#{employee.display_name || employee.phone_e164} shared more after completion",
              summary: "Discovery reopened (addendum ##{addendum}) with more questions available")
    end

    def self.intelligence_refreshed!(company:, summary: nil)
      create!(
        company: company,
        event_type: "intelligence_refreshed",
        target: company,
        title: "Intelligence refreshed",
        summary: summary.presence || "Signals, patterns, and readiness recomputed from current evidence"
      )
    end

    def self.create!(company:, event_type:, target:, title:, summary:)
      InsightTimelineEvent.create!(
        company: company,
        event_type: event_type,
        target_type: target.class.name,
        target_id: target.id,
        title: title,
        summary: summary,
        occurred_at: Time.current
      )
    end
  end
end
