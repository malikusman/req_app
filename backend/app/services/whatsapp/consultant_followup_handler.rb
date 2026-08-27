# frozen_string_literal: true

module Whatsapp
  class ConsultantFollowupHandler
    def initialize(employee:, conversation:, text:, external_id:, client:)
      @employee = employee
      @conversation = conversation
      @text = text
      @external_id = external_id
      @client = client
    end

    def handle
      request = ConsultantInfoRequest.open_for_employee(@employee.id)
      return false unless request

      message = @conversation.messages.create!(
        direction: "inbound",
        message_type: "text",
        body: @text,
        external_id: @external_id,
        consultant_followup: true,
        track: "consultant_followup",
        track_ref: request,
        raw_payload: { consultant_info_request_id: request.id }
      )

      ConsultantInfoReply.create!(
        consultant_info_request: request,
        message: message,
        body: @text,
        received_at: Time.current
      )

      request.update!(status: "replied")
      @conversation.update!(last_activity_at: Time.current)

      NotificationService.notify_info_reply_received(
        consultant: request.consultant_user,
        request: request,
        employee: @employee
      )

      true
    end
  end
end
