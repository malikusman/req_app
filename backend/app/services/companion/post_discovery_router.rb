# frozen_string_literal: true

module Companion
  # Routes post-completion inbound: companion by default; reopen only for addendum / promote.
  class PostDiscoveryRouter
    PROMOTE_PROMPT =
      "Thanks — I've noted that. Want me to add it to your discovery interview " \
      "so it can inform the company report? Reply yes to add it.".freeze

    def self.call(conversation:, employee:, user_message:, inbound_message: nil, channel: "whatsapp", client: nil)
      new(
        conversation: conversation,
        employee: employee,
        user_message: user_message,
        inbound_message: inbound_message,
        channel: channel,
        client: client
      ).call
    end

    def initialize(conversation:, employee:, user_message:, inbound_message: nil, channel: "whatsapp", client: nil)
      @conversation = conversation
      @employee = employee
      @user_message = user_message.to_s.strip
      @inbound_message = inbound_message
      @channel = channel
      @client = client
    end

    def call
      classification = IntentClassifier.call(
        text: @user_message,
        recent_messages: recent_bodies,
        awaiting_promote_confirm: NoteStore.awaiting_promote_confirm?(@conversation)
      )
      intent = classification[:intent]

      case intent
      when "promote_confirm"
        handle_promote_confirm
      when "addendum"
        handle_addendum
      when "tools"
        handle_tools
      when "share"
        handle_share
      else
        # ask / casual / unknown
        handle_companion(intent)
      end
    end

    private

    def recent_bodies
      @conversation.messages.order(created_at: :desc).limit(4).pluck(:body).compact
    end

    def handle_promote_confirm
      pending = NoteStore.clear_awaiting_promote!(@conversation)
      body = pending.presence || @user_message
      reopen_and_discover(body)
    end

    def handle_addendum
      NoteStore.clear_awaiting_promote!(@conversation) if NoteStore.awaiting_promote_confirm?(@conversation)
      reopen_and_discover(@user_message)
    end

    def handle_tools
      NoteStore.append_note!(conversation: @conversation, body: @user_message, intent: "tools")
      payload = ToolsSuggestService.call(employee: @employee, query: @user_message)
      deliver(
        "assistant_message" => payload[:assistant_message],
        "completed" => true,
        "question_count" => @conversation.question_count,
        "routing_decision" => {
          "action" => "companion_tools",
          "agent" => "companion",
          "intent" => "tools",
          "company_hits" => payload[:company].size,
          "general_hits" => payload[:general].size
        },
        "active_agent_id" => "companion"
      )
      @conversation
    end

    def handle_share
      NoteStore.append_note!(conversation: @conversation, body: @user_message, intent: "share")
      NoteStore.mark_awaiting_promote!(conversation: @conversation, pending_body: @user_message)
      deliver(
        "assistant_message" => PROMOTE_PROMPT,
        "completed" => true,
        "question_count" => @conversation.question_count,
        "routing_decision" => {
          "action" => "companion_share_prompt",
          "agent" => "companion",
          "intent" => "share"
        },
        "active_agent_id" => "companion"
      )
      @conversation
    end

    def handle_companion(intent)
      result = ProcessTurnService.call(
        conversation: @conversation,
        employee: @employee,
        user_message: @user_message,
        intent: intent
      )
      deliver(result)
      @conversation
    end

    def reopen_and_discover(text)
      @conversation = Discovery::ReopenConversationService.call(
        conversation: @conversation,
        employee: @employee
      )
      result = Discovery::ProcessTurnService.call(
        conversation: @conversation,
        employee: @employee,
        user_message: text,
        inbound_message: @inbound_message
      )
      deliver(result)
      @conversation
    end

    def deliver(result)
      Discovery::DeliverReply.call(
        conversation: @conversation,
        employee: @employee,
        result: result.is_a?(Hash) ? result.stringify_keys : result,
        channel: @channel == "web" ? :web : :whatsapp,
        client: @client
      )
    end
  end
end
