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
      return execute_turn unless @inbound_message

      turn = Discovery::DurableTurn.register(@conversation, @inbound_message, @user_message)
      return Discovery::DurableTurn.waiting(turn) if DiscoveryRequest.admitting

      @durable_turn = true
      @defer_on_failure = false
      Discovery::DurableTurn.call(self, turn)
    end

    def execute_turn
      playbook = nil
      if @conversation.state_snapshot['discovery_engine_version'] == 2 && !@conversation.blackboard['employee_discovery_v2'].is_a?(Hash)
        raise Langgraph::UnavailableError.new('Versioned interview state is missing', retryable: false, code: 'invalid_discovery_v2_state')
      end
      ensure_thread!
      playbook = DiscoveryPlaybook.active_playbook_for(@employee.department.presence || "default")
      raise Langgraph::UnavailableError.new("no_playbook", retryable: false) unless playbook

      if OpenaiCircuitBreaker.open?
        # Do NOT re-trip: trip! is a setex, so tripping an already-open breaker
        # refreshes its TTL. Under continuous traffic that turns a 300s cool-off
        # into a permanent block — the breaker can never expire because every
        # request it rejects extends it.
        return handle_unavailable!(playbook: playbook, trip_breaker: false)
      end

      agent_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = @client.run_turn!(
        thread_id: @conversation.langgraph_thread_id,
        user_message: EmployeeContext.redact(@user_message),
        playbook: playbook,
        context: build_context(playbook),
        history: build_history,
        multi_agent: multi_agent_payload
      )

      @agent_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - agent_started
      validate_workflow_contract!(result)
      @turn_playbook = playbook
      persist_turn!(result, playbook) unless @durable_turn
      OpenaiCircuitBreaker.reset!
      result
    rescue Langgraph::UnavailableError => e
      Rails.logger.warn("[Discovery::ProcessTurn] conversation_id=#{@conversation.id} source_message_id=#{@inbound_message&.id} code=#{e.code} retryable=#{e.retryable} reason=#{e.message}")
      handle_unavailable!(
        playbook: playbook,
        trip_breaker: e.retryable,
        defer: e.retryable,
        retryable: e.retryable,
        error_code: e.code
      )
    end

    # Time spent inside the agent call, for the per-turn timing log.
    attr_reader :agent_seconds

    private

    def validate_workflow_contract!(result)
      if employee_discovery_v2?
        V2Contract.prepare!(result, conversation: @conversation, source: @inbound_message)
        return
      end
      workflow = result.dig("blackboard", "dossier", "workflow")
      if @conversation.dossier["workflow"].is_a?(Hash) && !workflow.is_a?(Hash)
        raise Langgraph::UnavailableError.new("missing_workflow_contract", retryable: false)
      end
      return unless result["completed"] && workflow.is_a?(Hash)

      valid = %w[successful needs_follow_up employee_stopped].include?(workflow["outcome"])
      if workflow["outcome"] == "successful"
        confirmation = workflow["confirmation"] || {}
        valid &&= workflow["tasks"].is_a?(Array) && workflow["tasks"].any? &&
          confirmation["revision"] == workflow["revision"] && confirmation["summary_sha256"].present?
      end
      raise Langgraph::UnavailableError.new("invalid_workflow_completion", retryable: false) unless valid
    end

    def ensure_thread!
      return if @conversation.langgraph_thread_id.present?

      thread_id = @client.create_thread!
      @conversation.update!(langgraph_thread_id: thread_id)
    end

    def build_context(playbook)
      target = @conversation.effective_question_target
      agent_profile = EmployeeContext.basics(@company)
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
      }.compact.merge(employee_discovery_v2? ? { engine_version: 2, context_policy: EmployeeContext.policy(@conversation) } : {})
    end

    def build_history
      # Multi-agent turns lean on the rolling summary, but too small a raw window
      # meant the model couldn't see the interview's opening questions by mid-flow
      # and re-asked them — keep enough recent turns for an explicit anti-repeat guard.
      window = multi_agent_enabled? ? 80 : 24
      history = @conversation.messages
      history = history.where(track: %w[discovery profiling])
      # WhatsApp can queue several answers before the first model call finishes.
      # A turn must never consume a later answer as part of its own history.
      history = history.where("direction = 'outbound' OR id <= ?", @inbound_message.id) if @inbound_message
      history.order(:created_at, :id).last(window).filter_map do |msg|
        next if msg.body.blank?
        next if msg.message_type == "system"
        # A "brief delay" apology is not something the interviewer said — it is a
        # retry placeholder. Feeding it back as history poisoned every subsequent
        # attempt: the anti-repeat guard told the model not to repeat a non-question,
        # and each further failure added another one, compounding into a spiral a
        # single transient hiccup could never recover from.
        next if msg.raw_payload.is_a?(Hash) && msg.raw_payload["kind"] == "delay_notice"

        role = msg.direction == "outbound" ? "assistant" : "user"
        { role: role, content: EmployeeContext.redact(msg.body), message_id: msg.id,
          area: msg.routing_decision&.dig("area"), task_id: msg.routing_decision&.dig("task_id") }.compact
      end
    end

    def multi_agent_enabled?
      @company.merged_settings["discovery_multi_agent_enabled"] == true
    end

    def employee_discovery_v2?
      EmployeeContext.v2?(@conversation)
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
        source_message_id: @inbound_message&.id,
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
      snapshot['discovery_engine_version'] = 2 if result.dig('blackboard', 'employee_discovery_v2')

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

    def handle_unavailable!(playbook: nil, trip_breaker: true, defer: nil, retryable: true, error_code: "openai_unavailable")
      # Only trip a CLOSED breaker. trip! is a setex, so calling it while open
      # refreshes the cool-off window and the breaker never reopens under load.
      OpenaiCircuitBreaker.trip! if trip_breaker && !OpenaiCircuitBreaker.open?
      lang = @employee.preferred_language.presence || @company.locale
      defer = @defer_on_failure if defer.nil?

      if defer && @defer_on_failure
        RetryDiscoveryTurnJob.set(wait: 30.seconds).perform_later(
          @conversation.id,
          @user_message,
          @inbound_message&.id,
          1
        )
      end

      {
        "assistant_message" => retryable ? DELAY_MESSAGES.fetch(lang, DELAY_MESSAGES["en"]) :
          "Your answers are saved. The interview service needs administrator attention before it can continue. Please contact your company administrator, then retry your saved answer.",
        "completed" => false,
        "delayed" => true,
        "retryable" => retryable,
        "error_code" => error_code,
        "playbook_version" => playbook&.version
      }
    end
  end
end
