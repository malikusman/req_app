# frozen_string_literal: true

module Discovery
  # Reopens a completed conversation so the employee can share more (FEAT-ADDMORE).
  #
  # The interview now ends on a filled dossier rather than a counter, so reopening
  # is no longer about granting question budget: it raises the ceiling for the
  # addendum, clears the stall counter (the previous close may have been a stall),
  # and lets the flow ask for whatever the addendum leaves open.
  class ReopenConversationService
    ADDENDUM_NOTE = "Employee volunteered additional info after completion."

    def self.call(conversation:, employee:)
      new(conversation: conversation, employee: employee).call
    end

    def initialize(conversation:, employee:)
      @conversation = conversation
      @employee = employee
      @company = employee.company
    end

    def call
      return @conversation unless @conversation.completed?

      budget = addendum_budget
      current_count = @conversation.question_count.to_i
      new_ceiling = current_count + budget

      snapshot = @conversation.state_snapshot.merge(
        # Per-conversation ceiling override, read by Conversation#max_questions.
        # question_target is kept in step for the legacy single-agent path.
        "max_questions" => new_ceiling,
        "question_target" => new_ceiling,
        "addendum_count" => @conversation.state_snapshot.fetch("addendum_count", 0).to_i + 1,
        "reopened_at" => Time.current.iso8601,
        "blackboard" => reopen_blackboard(@conversation.blackboard)
      )

      @conversation.update!(
        status: "discovery",
        state_snapshot: snapshot,
        last_activity_at: Time.current
      )

      Intelligence::TimelineRecorder.conversation_reopened!(
        company: @company,
        employee: @employee,
        conversation: @conversation
      )

      @conversation
    end

    private

    def addendum_budget
      budget = @company.merged_settings.fetch("discovery_addendum_budget", 3).to_i
      budget.positive? ? budget : 3
    end

    def reopen_blackboard(blackboard)
      bb = (blackboard.presence || {}).deep_dup
      summary = bb["conversation_summary"].to_s
      bb["conversation_summary"] = [summary, ADDENDUM_NOTE].reject(&:blank?).join("\n")
      # The previous close may have been a stall; starting the addendum already
      # stalled would end it on the first turn.
      bb["stall_turns"] = 0
      bb.delete("close_reason")
      bb
    end
  end
end
