# frozen_string_literal: true

module Intelligence
  class TimelineRecorder
    # These two land on the CLIENT dashboard, so they are written for the person
    # paying for the report, not for us. They used to read "Strength increased to
    # 0.57 across 5 mentions" — our model's vocabulary and a raw score, in front
    # of a customer. The evidence count is the part that actually means something
    # to them, so that is what is said.
    def self.signal_detected!(company:, signal:)
      create!(company: company, event_type: "signal_detected", target: signal,
              title: signal.label,
              summary: "First raised #{where_phrase(signal)}")
    end

    def self.signal_strengthened!(company:, signal:)
      count = signal.evidence_count.to_i
      create!(company: company, event_type: "signal_strengthened", target: signal,
              title: signal.label,
              summary: "Now raised in #{count} #{'conversation'.pluralize(count)} #{where_phrase(signal)}")
    end

    # "in finance and operations", or "in discovery" when no department is known.
    def self.where_phrase(signal)
      departments = Array(signal.departments).reject(&:blank?)
      return "in discovery" if departments.empty?
      return "in #{departments.first}" if departments.one?

      "across #{departments[0..-2].join(', ')} and #{departments.last}"
    end
    private_class_method :where_phrase

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
