# frozen_string_literal: true

module Discovery
  # Persists assistant replies and optionally delivers them over WhatsApp.
  class DeliverReply
    def self.call(conversation:, employee:, result:, channel: :whatsapp, client: nil)
      new(conversation: conversation, employee: employee, result: result, channel: channel, client: client).call
    end

    def initialize(conversation:, employee:, result:, channel:, client:)
      @conversation = conversation
      @employee = employee
      @result = result
      @channel = channel
      @client = client || Whatsapp::MetaClient.new
    end

    def call
      if @result["delayed"]
        body = @result["assistant_message"].to_s
        # Tagged so build_history can exclude it. Untagged, this canned apology was
        # persisted as an ordinary discovery message and fed straight back to the
        # model on the retry as if it were a real turn — with the anti-repeat guard
        # then instructing the model "do NOT repeat this", a nonsensical constraint.
        # One transient failure compounded into an unrecoverable spiral: every retry
        # added another delay notice to history, making the next attempt more
        # confusing than the last.
        return persist_outbound(body, is_discovery_question: false, delay_notice: true) if body.present?
        return nil
      end

      assistant_body = @result["assistant_message"].to_s
      return nil if assistant_body.blank?

      is_question = !@result["completed"] && @conversation.reload.question_count.positive?
      message = persist_outbound(
        assistant_body,
        is_discovery_question: is_question,
        agent_id: agent_id_from(@result),
        routing_decision: @result["routing_decision"]
      )

      if @channel == :whatsapp && @client.configured?
        @client.send_text(to: @employee.phone_e164, body: assistant_body)
      elsif @channel == :whatsapp
        Rails.logger.info("[WhatsApp dev] to=#{@employee.phone_e164} body=#{assistant_body}")
      end

      message
    end

    private

    def persist_outbound(body, is_discovery_question:, agent_id: nil, routing_decision: nil, delay_notice: false)
      Message.create!(
        conversation: @conversation,
        direction: "outbound",
        channel: @channel == :web ? "web" : "whatsapp",
        message_type: "text",
        body: body,
        is_discovery_question: is_discovery_question,
        agent_id: agent_id,
        routing_decision: routing_decision.presence || {},
        # message_type stays "text" (not "system") so the employee still sees the
        # apology in their own thread — only build_history needs to exclude it.
        raw_payload: delay_notice ? { "kind" => "delay_notice" } : {}
      )
    end

    def agent_id_from(result)
      decision = result["routing_decision"]
      return decision["agent"] if decision.is_a?(Hash) && decision["agent"].present?

      result["active_agent_id"].presence
    end
  end
end
