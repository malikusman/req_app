# frozen_string_literal: true

module Inbound
  # Decides which track an inbound employee message belongs to, and dispatches it.
  #
  # This precedence used to live only in Whatsapp::InboundProcessor, which meant a
  # consultant's question answered on the web thread was swallowed by the discovery
  # handler — the web router went straight to profiling/discovery/onboarding. Both
  # channels now share this one ladder:
  #
  #   1. an open consultant question is awaiting an answer  -> consultant_followup
  #   2. ...unless the message is plainly about something else -> companion
  #   3. conversation not yet completed                     -> discovery (or onboarding/profiling)
  #   4. completed                                          -> companion
  #
  # Rung 2 matters more than it looks: without it an unanswered consultant question
  # blocks the companion indefinitely, so an employee asking "any tools for this?"
  # gets recorded as answering the consultant and pollutes the reply thread.
  class TrackRouter
    # Intents that are clearly not an answer to a pending question. Anything else —
    # including a bare statement of fact — is treated as the answer, because that is
    # what an employee replying to a question actually sends.
    NON_ANSWER_INTENTS = %w[tools casual].freeze

    def self.call(employee:, conversation:, text:, external_id: nil, channel: "whatsapp", client: nil)
      new(
        employee: employee,
        conversation: conversation,
        text: text,
        external_id: external_id,
        channel: channel,
        client: client
      ).call
    end

    def initialize(employee:, conversation:, text:, external_id: nil, channel: "whatsapp", client: nil)
      @employee = employee
      @conversation = conversation
      @text = text.to_s
      @external_id = external_id
      @channel = channel
      @client = client || Whatsapp::MetaClient.new
    end

    def call
      return :consultant_followup if route_to_consultant_followup?

      route_to_conversation_handler
    end

    private

    def handler_args
      {
        employee: @employee,
        conversation: @conversation,
        text: @text,
        external_id: @external_id,
        client: @client
      }
    end

    # Rung 1 + 2. Returns true only when an open request existed AND the message was
    # actually treated as its answer.
    def route_to_consultant_followup?
      channel = newest_consultant_request_channel
      return false unless channel
      return false unless answers_pending_question?

      case channel
      when :outreach     then Whatsapp::OutreachReplyHandler.new(**handler_args).handle
      when :info_request then Whatsapp::ReviewerFollowupHandler.new(**handler_args).handle
      else false
      end
    end

    # A consultant can have an open question in EITHER channel (ReviewerOutreach or
    # the legacy ReviewerInfoRequest). Attribute the reply to whichever opened most
    # recently, so a stale request can't hijack a reply meant for a newer question.
    def newest_consultant_request_channel
      outreach = ReviewerOutreach.open_whatsapp_for_employee(@employee.id)
      info = ReviewerInfoRequest.open_for_employee(@employee.id)
      return nil if outreach.nil? && info.nil?
      return :outreach if info.nil?
      return :info_request if outreach.nil?

      outreach_time = outreach.sent_at || outreach.created_at
      outreach_time >= info.created_at ? :outreach : :info_request
    end

    # Only asked once a request is actually open, so the classifier cost is paid on
    # the rare turn rather than every inbound message. Fail-safe: if classification
    # errors, treat the message as the answer — losing a consultant's reply is worse
    # than mis-filing a companion aside.
    def answers_pending_question?
      return true unless @conversation.completed?

      classification = Companion::IntentClassifier.call(
        text: @text,
        recent_messages: recent_bodies,
        awaiting_promote_confirm: false
      )
      !NON_ANSWER_INTENTS.include?(classification[:intent])
    rescue StandardError => e
      Rails.logger.warn("[Inbound::TrackRouter] intent check failed, treating as answer: #{e.class}: #{e.message}")
      true
    end

    def recent_bodies
      @conversation.messages.order(created_at: :desc).limit(4).pluck(:body).compact
    end

    # Rungs 3 + 4. Unchanged behaviour, just no longer duplicated per channel.
    def route_to_conversation_handler
      if @conversation.profiling?
        Whatsapp::ProfilingHandler
          .new(employee: @employee, conversation: @conversation, client: @client, channel: @channel)
          .handle_inbound_text(@text, external_id: @external_id)
        :profiling
      elsif @conversation.discovery? || @employee.onboarding_step == "verified"
        # DiscoveryHandler forwards to Companion::PostDiscoveryRouter once the
        # conversation is completed, so this arm covers both discovery and companion.
        Whatsapp::DiscoveryHandler
          .new(employee: @employee, conversation: @conversation, client: @client, channel: @channel)
          .handle_inbound_text(@text, external_id: @external_id)
        @conversation.completed? ? :companion : :discovery
      else
        Whatsapp::OnboardingHandler
          .new(employee: @employee, conversation: @conversation, client: @client, channel: @channel)
          .handle_inbound_text(@text, external_id: @external_id)
        :onboarding
      end
    end
  end
end
