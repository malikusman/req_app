# frozen_string_literal: true

module Discovery
  # Reopens a completed conversation so the employee can share more (FEAT-ADDMORE).
  # Grants a bounded question-target top-up from company setting discovery_addendum_budget.
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
      new_target = current_count + budget

      snapshot = @conversation.state_snapshot.merge(
        "question_target" => new_target,
        "addendum_count" => @conversation.state_snapshot.fetch("addendum_count", 0).to_i + 1,
        "reopened_at" => Time.current.iso8601,
        "blackboard" => top_up_blackboard(@conversation.blackboard, budget)
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

    def top_up_blackboard(blackboard, budget)
      bb = (blackboard.presence || {}).deep_dup
      summary = bb["conversation_summary"].to_s
      bb["conversation_summary"] = [summary, ADDENDUM_NOTE].reject(&:blank?).join("\n")

      states = bb["agent_states"]
      return bb unless states.is_a?(Hash) && states.any?

      preferred = bb["active_agent_id"].presence || bb.dig("agent_queue", 0, "id") || states.keys.first
      state = (states[preferred] || {}).dup
      asked = state["questions_asked"].to_i
      state["questions_asked"] = asked
      state["question_budget"] = asked + budget
      state["status"] = "active"
      state["open_threads"] ||= []
      states[preferred] = state
      bb["agent_states"] = states
      bb["active_agent_id"] = preferred

      if bb["agent_queue"].is_a?(Array)
        bb["agent_queue"] = bb["agent_queue"].map do |entry|
          next entry unless entry.is_a?(Hash) && entry["id"] == preferred

          entry.merge("question_budget" => asked + budget)
        end
      end

      bb["total_budget"] = bb["total_budget"].to_i + budget if bb.key?("total_budget")
      bb
    end
  end
end
