# frozen_string_literal: true

module Discovery
  class ProcessTurnService
    DELAY_MESSAGES = {
      "en" => "We're experiencing a brief delay — we'll pick up right where we left off shortly.",
      "es" => "Estamos teniendo una breve demora — continuaremos en breve justo donde lo dejamos.",
      "fr" => "Nous rencontrons un court délai — nous reprendrons bientôt.",
      "de" => "Es gibt eine kurze Verzögerung — wir machen gleich weiter."
    }.freeze

    def self.call(conversation:, employee:, user_message:, inbound_message: nil, defer_on_failure: true)
      new(conversation: conversation, employee: employee, user_message: user_message,
          inbound_message: inbound_message, defer_on_failure: defer_on_failure).call
    end

    def initialize(conversation:, employee:, user_message:, inbound_message: nil, defer_on_failure: true)
      @conversation = conversation
      @employee = employee
      @company = employee.company
      @user_message = user_message
      @inbound_message = inbound_message
      @defer_on_failure = defer_on_failure
      @client = Langgraph::Client.new
    end

    def call
      ensure_thread!
      playbook = DiscoveryPlaybook.active_playbook_for(@employee.department.presence || "default")
      raise Langgraph::UnavailableError, "no_playbook" unless playbook

      if OpenaiCircuitBreaker.open?
        return handle_unavailable!(playbook: playbook)
      end

      result = @client.run_turn!(
        thread_id: @conversation.langgraph_thread_id,
        user_message: @user_message,
        playbook: playbook,
        context: build_context(playbook),
        history: build_history,
        multi_agent: multi_agent_payload
      )

      persist_turn!(result, playbook)
      result
    rescue Langgraph::UnavailableError
      handle_unavailable!(playbook: playbook)
    end

    private

    def ensure_thread!
      return if @conversation.langgraph_thread_id.present?

      thread_id = @client.create_thread!
      @conversation.update!(langgraph_thread_id: thread_id)
    end

    def build_context(playbook)
      target = @company.merged_settings.fetch("discovery_question_target", 10).to_i
      {
        preferred_language: @employee.preferred_language.presence || @company.locale,
        company_name: @company.display_name || @company.name,
        employee_name: @employee.display_name.to_s,
        department: @employee.department.presence || "default",
        question_count: @conversation.question_count,
        question_target: target
      }
    end

    def build_history
      # Multi-agent turns rely on the rolling summary in the blackboard,
      # so only recent raw messages are needed; legacy turns keep the old window.
      window = multi_agent_enabled? ? 6 : 24
      @conversation.messages.order(:created_at).last(window).filter_map do |msg|
        next if msg.body.blank?
        next if msg.message_type == "system"

        role = msg.direction == "outbound" ? "assistant" : "user"
        { role: role, content: msg.body }
      end
    end

    def multi_agent_enabled?
      @company.merged_settings["discovery_multi_agent_enabled"] == true
    end

    def multi_agent_payload
      return nil unless multi_agent_enabled?

      context = Discovery::ContextBuilder.call(
        conversation: @conversation,
        employee: @employee,
        user_message: @user_message,
        inbound_message: @inbound_message
      )
      {
        profile: context[:profile],
        blackboard: context[:blackboard],
        limits: context[:limits],
        memory_facts: context[:memory_facts],
        document_snippets: context[:document_snippets],
        media_context: context[:media_context],
        media_snippets: context[:media_snippets]
      }
    end

    def persist_turn!(result, playbook)
      turn_number = @conversation.question_count + 1
      insight_data = result["insight"] || {}

      if insight_data["summary"].present?
        ConversationInsight.create!(
          conversation: @conversation,
          employee: @employee,
          company: @company,
          message: @inbound_message,
          turn_number: turn_number,
          insight_type: "turn_summary",
          summary: insight_data["summary"],
          structured_data: { "topics" => insight_data["topics"] || [] }
        )
      end

      snapshot = @conversation.state_snapshot.merge(
        "playbook_version" => playbook.version,
        "playbook_department" => playbook.department,
        "last_insight" => insight_data
      )

      if result["blackboard"].present?
        snapshot = snapshot.merge("blackboard" => result["blackboard"])
        snapshot = snapshot.merge("last_routing_decision" => result["routing_decision"]) if result["routing_decision"].present?
      end

      @conversation.update!(
        question_count: result["question_count"],
        state_snapshot: snapshot,
        last_activity_at: Time.current
      )

      if result["completed"]
        Discovery::FinalizeConversationService.call(conversation: @conversation, employee: @employee)
      end

      result
    end

    def handle_unavailable!(playbook: nil)
      OpenaiCircuitBreaker.trip!
      lang = @employee.preferred_language.presence || @company.locale

      if @defer_on_failure
        RetryDiscoveryTurnJob.set(wait: 30.seconds).perform_later(
          @conversation.id,
          @user_message,
          @inbound_message&.id,
          1
        )
      end

      {
        "assistant_message" => DELAY_MESSAGES.fetch(lang, DELAY_MESSAGES["en"]),
        "completed" => false,
        "delayed" => true,
        "playbook_version" => playbook&.version
      }
    end
  end
end
