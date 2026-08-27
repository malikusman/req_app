# frozen_string_literal: true

module Whatsapp
  class ReviewerFollowupHandler
    def initialize(employee:, conversation:, text:, external_id:, client:)
      @employee = employee
      @conversation = conversation
      @text = text
      @external_id = external_id
      @client = client
    end

    def handle
      request = ReviewerInfoRequest.open_for_employee(@employee.id)
      return false unless request

      message = @conversation.messages.create!(
        direction: "inbound",
        message_type: "text",
        body: @text,
        external_id: @external_id,
        reviewer_followup: true,
        track: "consultant_followup",
        track_ref: request,
        raw_payload: { reviewer_info_request_id: request.id }
      )

      ReviewerInfoReply.create!(
        reviewer_info_request: request,
        message: message,
        body: @text,
        received_at: Time.current
      )

      request.update!(status: "replied")
      @conversation.update!(last_activity_at: Time.current)

      NotificationService.notify_info_reply_received(
        reviewer: request.reviewer_user,
        request: request,
        employee: @employee
      )

      true
    end
  end
end
