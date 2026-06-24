# frozen_string_literal: true

module Discovery
  # Kicks off discovery proactively after consent (or profiling completion):
  # routes agents when needed, persists a system kickoff inbound, shows typing,
  # runs the first LangGraph turn, and delivers the assistant reply.
  class ProactiveStartService
    def self.call(conversation:, employee:, client: Whatsapp::MetaClient.new, trigger_message_id: nil,
                  delivery_channel: :whatsapp)
      new(conversation: conversation, employee: employee, client: client,
          trigger_message_id: trigger_message_id, delivery_channel: delivery_channel).call
    end

    def initialize(conversation:, employee:, client:, trigger_message_id: nil, delivery_channel: :whatsapp)
      @conversation = conversation
      @employee = employee
      @company = employee.company
      @client = client
      @trigger_message_id = trigger_message_id
      @delivery_channel = delivery_channel
    end

    def call
      merge_profile_into_blackboard!
      route_agents!
      kickoff_body = KickoffMessage.build(employee: @employee)
      inbound = persist_kickoff!(kickoff_body)
      show_typing_indicator!

      result = ProcessTurnService.call(
        conversation: @conversation,
        employee: @employee,
        user_message: kickoff_body,
        inbound_message: inbound
      )

      Discovery::DeliverReply.call(
        conversation: @conversation,
        employee: @employee,
        result: result,
        channel: @delivery_channel,
        client: @client
      )
    end

    private

    def merge_profile_into_blackboard!
      return unless @employee.profile_complete?
      return if @conversation.blackboard["profile"].present?

      @conversation.update_blackboard!("profile" => @employee.profile_card)
    end

    def route_agents!
      return unless @company.merged_settings["discovery_multi_agent_enabled"]

      result = Langgraph::Client.new.route!(
        thread_id: ensure_thread_id,
        profile: @employee.profile_card,
        limits: ContextBuilder.limits_for(@company),
        context: { question_target: @company.merged_settings.fetch("discovery_question_target", 10).to_i }
      )
      @conversation.update_blackboard!(
        "agent_queue" => result["agents"],
        "skipped_agents" => result["skipped"],
        "total_budget" => result["total_budget"]
      )
    rescue Langgraph::UnavailableError => e
      Rails.logger.warn("[ProactiveStart] agent routing failed, deferring to first turn: #{e.message}")
    end

    def ensure_thread_id
      return @conversation.langgraph_thread_id if @conversation.langgraph_thread_id.present?

      thread_id = Langgraph::Client.new.create_thread!
      @conversation.update!(langgraph_thread_id: thread_id)
      thread_id
    end

    def persist_kickoff!(body)
      Message.create!(
        conversation: @conversation,
        direction: "inbound",
        message_type: "system",
        channel: @delivery_channel == :web ? "web" : "whatsapp",
        body: body,
        raw_payload: { "kind" => "discovery_kickoff" },
        is_discovery_question: false
      )
    end

    def show_typing_indicator!
      return unless @trigger_message_id.present?

      @client.send_typing_on(message_id: @trigger_message_id)
    rescue Whatsapp::MetaClient::ApiError => e
      Rails.logger.warn("[ProactiveStart] typing indicator failed: #{e.message}")
    end
  end
end
