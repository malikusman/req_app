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
      playbook = nil
      ensure_thread!
      playbook = DiscoveryPlaybook.active_playbook_for(@employee.department.presence || "default")
      raise Langgraph::UnavailableError.new("no_playbook", retryable: false) unless playbook

      if OpenaiCircuitBreaker.open?
        return handle_unavailable!(playbook: playbook, trip_breaker: true)
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
      OpenaiCircuitBreaker.reset!
      result
    rescue Langgraph::UnavailableError => e
      Rails.logger.warn("[Discovery::ProcessTurn] #{e.message} retryable=#{e.retryable}")
      handle_unavailable!(
        playbook: playbook,
        trip_breaker: e.retryable,
        defer: e.retryable
      )
    end

    private

    def ensure_thread!
      return if @conversation.langgraph_thread_id.present?

      thread_id = @client.create_thread!
      @conversation.update!(langgraph_thread_id: thread_id)
    end

    def build_context(playbook)
      target = @conversation.effective_question_target
      agent_profile = Companies::AgentContext.for_agents(@company)
      {
        preferred_language: @employee.preferred_language.presence || @company.locale,
        company_name: @company.display_name || @company.name,
        employee_name: @employee.display_name.to_s,
        department: @employee.department.presence || "default",
        question_count: @conversation.question_count,
        question_target: target,
        industry: agent_profile["industry"],
        size_band: agent_profile["size_band"],
        region: agent_profile["region"].presence || agent_profile["country"],
        business_goals: agent_profile["business_goals"],
        website_url: agent_profile["website_url"],
        known_systems: agent_profile["known_systems"],
        company_profile: agent_profile
      }.compact
    end

    def build_history
      # Multi-agent turns lean on the rolling summary, but too small a raw window
      # meant the model couldn't see the interview's opening questions by mid-flow
      # and re-asked them — keep enough recent turns for an explicit anti-repeat guard.
      window = multi_agent_enabled? ? 14 : 24
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
      # A reopened conversation carries a raised ceiling, so the per-conversation
      # value wins over the company/ENV default the ContextBuilder resolved.
      limits = context[:limits].merge(max_questions: @conversation.max_questions)
      {
        profile: context[:profile],
        blackboard: context[:blackboard],
        limits: limits,
        memory_facts: context[:memory_facts],
        document_snippets: context[:document_snippets],
        knowledge_snippets: context[:knowledge_snippets],
        media_context: context[:media_context],
        media_snippets: context[:media_snippets],
        company_profile: context[:company_profile],
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

    def handle_unavailable!(playbook: nil, trip_breaker: true, defer: nil)
      OpenaiCircuitBreaker.trip! if trip_breaker
      lang = @employee.preferred_language.presence || @company.locale
      defer = @defer_on_failure if defer.nil?

      if defer
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
