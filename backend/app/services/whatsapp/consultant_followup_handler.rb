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

      # Shared with the emailed-reply path so an answer lands identically whichever
      # way it arrives — including advancing the consultant's requirement loop.
      ConsultantFollowup::RecordReplyService.call(
        request: request,
        body: @text,
        channel: "whatsapp",
        external_id: @external_id
      )

      true
    end
  end
end
