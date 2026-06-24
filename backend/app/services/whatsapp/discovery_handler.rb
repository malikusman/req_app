# frozen_string_literal: true

module Whatsapp
  class DiscoveryHandler
    def initialize(employee:, conversation:, client: MetaClient.new, channel: "whatsapp")
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @client = client
      @channel = channel
    end

    def handle_inbound_text(text, external_id: nil)
      text = text.to_s.strip
      return handle_opt_out if opt_out?(text)

      @conversation.touch_activity!
      @employee.update!(last_active_at: Time.current)

      inbound = persist_message(direction: "inbound", body: text, external_id: external_id)
      process_user_message(text, inbound_message: inbound)
    end

    def process_extracted_text(text, inbound_message:)
      @conversation.touch_activity!
      @employee.update!(last_active_at: Time.current)
      process_user_message(text, inbound_message: inbound_message)
    end

    def process_user_message(text, inbound_message:)
      result = Discovery::ProcessTurnService.call(
        conversation: @conversation,
        employee: @employee,
        user_message: text,
        inbound_message: inbound_message
      )

      deliver_assistant_reply(result)
    end

    def deliver_assistant_reply(result)
      Discovery::DeliverReply.call(
        conversation: @conversation,
        employee: @employee,
        result: result,
        channel: @channel == "web" ? :web : :whatsapp,
        client: @client
      )
    end

    private

    def handle_opt_out
      @employee.update!(participation_status: "declined")
      @conversation.update!(status: "abandoned", abandoned_at: Time.current, abandon_reason: "opt_out")
      send_text("You've been unsubscribed. Reply anytime if your admin sends a new invitation.")
    end

    def opt_out?(text)
      %w[stop unsubscribe cancel].include?(text.downcase)
    end

    def send_text(body, is_discovery_question: false, agent_id: nil, routing_decision: nil)
      persist_message(
        direction: "outbound",
        body: body,
        is_discovery_question: is_discovery_question,
        agent_id: agent_id,
        routing_decision: routing_decision
      )
      if @client.configured?
        @client.send_text(to: @employee.phone_e164, body: body)
      else
        Rails.logger.info("[WhatsApp dev] to=#{@employee.phone_e164} body=#{body}")
      end
    end

    def persist_message(direction:, body:, external_id: nil, is_discovery_question: false, agent_id: nil,
                        routing_decision: nil)
      Message.create!(
        conversation: @conversation,
        direction: direction,
        channel: @channel,
        message_type: "text",
        body: body,
        external_id: external_id,
        is_discovery_question: is_discovery_question,
        agent_id: agent_id,
        routing_decision: routing_decision.presence || {}
      )
    end
  end
end
