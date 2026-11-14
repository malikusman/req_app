# frozen_string_literal: true

module Platform
  # How each company's interviews are going, for running a pilot: who finished,
  # who drifted off, how the interviews closed, whether the recording step is
  # failing, and whether the findings carry hours. Counts only — no content.
  #
  # Every figure is here because it answers a question someone running a pilot
  # asks: "are people finishing?", "is anything broken?", "will the report have
  # numbers in it?". The flags say which of those needs a look.
  class InterviewHealth
    QUIET_AFTER = 24.hours
    IN_PROGRESS = %w[onboarding profiling discovery].freeze

    def self.call(since: 30.days.ago)
      new(since: since).call
    end

    def initialize(since:)
      @since = since
    end

    def call
      company_ids = Conversation.where("created_at >= ?", @since).distinct.pluck(:company_id)
      Company.where(id: company_ids).order(:name).map { |company| row(company) }
             .sort_by { |r| [-r[:flags].size, r[:company][:name].to_s] }
    end

    private

    def row(company)
      conversations = company.conversations.where("created_at >= ?", @since)
      ids = conversations.select(:id)
      statuses = conversations.group(:status).count
      closes = conversations.where(status: %w[completed abandoned])
                            .pluck(Arel.sql("state_snapshot->'blackboard'->>'close_reason'")).compact.tally
      quiet = conversations.where(status: IN_PROGRESS).where("last_activity_at < ?", QUIET_AFTER.ago).count
      questions = conversations.where(status: "completed").pluck(:question_count).sort

      turns = Message.where(conversation_id: ids, direction: "outbound").where("routing_decision ? 'capture'")
      captures = turns.group(Arel.sql("routing_decision->>'capture'")).count
      captured = captures.values.sum
      fallbacks = captured - captures.fetch("recorded", 0) - captures.fetch("skipped", 0)

      findings = company.findings.where(conversation_id: ids)
      live = findings.where.not(status: %w[hidden merged])
      voice = Message.where(conversation_id: ids, direction: "inbound", message_type: "audio")
      voice_failed = MediaAttachment.where(conversation_id: ids, attachment_type: "audio", status: "failed").count

      row = {
        company: { id: company.id, name: company.display_name || company.name, slug: company.slug },
        interviews: {
          invited: company.employees.where("invited_at >= ?", @since).count,
          started: conversations.count,
          completed: statuses.fetch("completed", 0),
          abandoned: statuses.fetch("abandoned", 0),
          in_progress: IN_PROGRESS.sum { |s| statuses.fetch(s, 0) },
          quiet: quiet
        },
        closes: closes,
        median_questions: questions.empty? ? nil : questions[questions.size / 2],
        capture: { turns: captured, fallbacks: fallbacks },
        findings: { live: live.count, with_hours: live.where.not(annual_hours_min: nil).count,
                    to_review: live.to_a.count(&:needs_review?) },
        voice: { answers: voice.count, failed: voice_failed }
      }
      row.merge(flags: flags(row))
    end

    def pluralize(count, word) = "#{count} #{count == 1 ? word : word.pluralize}"

    def flags(row)
      interviews = row[:interviews]
      closed = row[:closes].values.sum
      out = []
      out << "#{interviews[:quiet]} in progress but quiet for over a day" if interviews[:quiet].positive?
      if row[:capture][:turns] >= 10 && row[:capture][:fallbacks].to_f / row[:capture][:turns] > 0.05
        out << "#{row[:capture][:fallbacks]} of #{row[:capture][:turns]} answers were not recorded"
      end
      stalled = row[:closes].fetch("stalled", 0) + row[:closes].fetch("ceiling", 0)
      if closed >= 3 && stalled.to_f / closed > 0.3
        out << "#{stalled} of #{closed} interviews ended without covering the role"
      end
      if row[:findings][:live] >= 5 && row[:findings][:with_hours].to_f / row[:findings][:live] < 0.5
        out << "only #{row[:findings][:with_hours]} of #{row[:findings][:live]} findings have hours"
      end
      if row[:voice][:failed].positive?
        out << "#{pluralize(row[:voice][:failed], 'spoken answer')} failed to transcribe"
      end
      if row[:findings][:to_review].positive?
        out << "#{pluralize(row[:findings][:to_review], 'finding')} waiting for consultant review"
      end
      out
    end
  end
end
