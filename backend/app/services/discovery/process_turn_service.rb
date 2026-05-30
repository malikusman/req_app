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
      @use_v2 = Companies::AgentFeatures.enabled?(@company, :multi_agent_discovery)
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
        use_v2: @use_v2
      )

      persist_turn!(result, playbook)
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
        company_id: @company.id,
        employee_id: @employee.id,
        employee_name: @employee.display_name.to_s,
        department: @employee.department.presence || "default",
        question_count: @conversation.question_count,
        question_target: target,
        employee_profile: @employee.agent_profile || {}
      }
    end

    def build_history
      @conversation.messages.order(:created_at).last(24).filter_map do |msg|
        next if msg.body.blank?

        role = msg.direction == "outbound" ? "assistant" : "user"
        { role: role, content: msg.body }
      end
    end

    def persist_turn!(result, playbook)
      turn_number = @conversation.question_count + 1
      insight_data = result["insight"] || {}
      insight_record = nil

      if insight_data["summary"].present?
        insight_record = ConversationInsight.create!(
          conversation: @conversation,
          employee: @employee,
          company: @company,
          message: @inbound_message,
          turn_number: turn_number,
          insight_type: "turn_summary",
          summary: insight_data["summary"],
          structured_data: { "topics" => insight_data["topics"] || [] }
        )
        Knowledge::IndexInsightJob.perform_later(insight_record.id)
      end

      profile = result["employee_profile"].presence
      @employee.update!(agent_profile: profile) if profile.present?

      snapshot = @conversation.state_snapshot.merge(
        "playbook_version" => playbook.version,
        "playbook_department" => playbook.department,
        "last_insight" => insight_data,
        "last_confidence" => result["confidence"]
      )

      updates = {
        question_count: result["question_count"],
        state_snapshot: snapshot,
        last_activity_at: Time.current
      }

      if result["completed"]
        Discovery::FinalizeConversationService.call(conversation: @conversation, employee: @employee)
      else
        @conversation.update!(updates)
      end

      if @use_v2 && result["requires_hitl"]
        create_interrupt!(result)
        result["interrupted"] = true
        result["assistant_message"] = ""
      end

      result
    end

    def create_interrupt!(result)
      AgentInterrupt.create!(
        thread_id: @conversation.langgraph_thread_id,
        company: @company,
        employee: @employee,
        conversation: @conversation,
        kind: "discovery_reply",
        status: "pending",
        payload: {
          "assistant_message" => result["assistant_message"],
          "confidence" => result["confidence"],
          "hitl_reason" => result["hitl_reason"],
          "user_message" => @user_message
        }
      )
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
