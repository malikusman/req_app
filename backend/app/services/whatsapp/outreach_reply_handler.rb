# frozen_string_literal: true

module Whatsapp
  # Routes inbound WhatsApp text to an open ReviewerOutreach (sent clarification),
  # before falling back to legacy ReviewerInfoRequest follow-ups.
  class OutreachReplyHandler
    def initialize(employee:, conversation:, text:, external_id:, client:)
      @employee = employee
      @conversation = conversation
      @text = text
      @external_id = external_id
      @client = client
    end

    def handle
      outreach = ReviewerOutreach.open_whatsapp_for_employee(@employee.id)
      return false unless outreach

      message = @conversation.messages.create!(
        direction: "inbound",
        message_type: "text",
        body: @text,
        external_id: @external_id,
        reviewer_followup: true,
        track: "consultant_followup",
        track_ref: outreach,
        raw_payload: { "reviewer_outreach_id" => outreach.id }
      )

      Outreaches::RecordReplyService.call(
        outreach: outreach,
        body: @text,
        channel: "whatsapp",
        message_id: message.id.to_s
      )

      @conversation.update!(last_activity_at: Time.current)
      true
    end
  end
end
