# frozen_string_literal: true

module Outreaches
  class RecordReplyService
    def self.call(outreach:, body:, channel:, message_id: nil, company_user: nil)
      new(outreach: outreach, body: body, channel: channel, message_id: message_id, company_user: company_user).call
    end

    def initialize(outreach:, body:, channel:, message_id: nil, company_user: nil)
      @outreach = outreach
      @body = body
      @channel = channel
      @message_id = message_id
      @company_user = company_user
    end

    def call
      reply = ReviewerOutreachReply.create!(
        reviewer_outreach: @outreach,
        channel: @channel,
        body: @body,
        message_id: @message_id,
        company_user: @company_user,
        received_at: Time.current
      )
      @outreach.update!(status: "replied")
      @outreach.append_audit!("replied", actor: @company_user || @outreach.employee || @outreach.reviewer_user)

      if NotificationService.respond_to?(:notify_outreach_reply)
        NotificationService.notify_outreach_reply(outreach: @outreach, reply: reply)
      end

      reply
    end
  end
end
