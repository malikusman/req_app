# frozen_string_literal: true

module ConsultantFollowup
  # Records an employee's answer to a consultant follow-up, whatever channel it
  # arrived on.
  #
  # Extracted from Whatsapp::ConsultantFollowupHandler so an emailed reply lands
  # exactly like a WhatsApp one: a message in the employee's own thread, a stored
  # reply, the request closed, and — if the question came from a stated need — the
  # requirement re-evaluated.
  #
  # That last part is why this must be shared rather than reimplemented: a reply
  # arriving by email has to advance the requirement loop too, or a consultant sees
  # their question answered and their need still open.
  class RecordReplyService
    def self.call(request:, body:, channel:, external_id: nil)
      new(request: request, body: body, channel: channel, external_id: external_id).call
    end

    def initialize(request:, body:, channel:, external_id: nil)
      @request = request
      @body = body.to_s.strip
      @channel = channel.to_s
      @external_id = external_id
    end

    def call
      raise ArgumentError, "Reply body is required" if @body.blank?

      message = persist_message!
      ConsultantInfoReply.create!(
        consultant_info_request: @request,
        message: message,
        body: @body,
        received_at: Time.current
      )

      @request.update!(status: "replied")
      @request.conversation.update!(last_activity_at: Time.current)

      NotificationService.notify_info_reply_received(
        consultant: @request.consultant_user,
        request: @request,
        employee: @request.employee
      )

      advance_requirement_loop!(message)
      message
    end

    private

    # The reply belongs in the employee's thread, not just in the request — that is
    # what makes an emailed answer visible where they are talking to us.
    def persist_message!
      @request.conversation.messages.create!(
        direction: "inbound",
        message_type: "text",
        channel: @channel == "whatsapp" ? "whatsapp" : "web",
        body: @body,
        external_id: @external_id,
        track: "consultant_followup",
        track_ref: @request,
        raw_payload: { "consultant_info_request_id" => @request.id, "reply_channel" => @channel }
      )
    end

    # Never raises: the reply is already stored by this point, and losing it to an
    # evaluation error would be far worse than an unevaluated requirement.
    def advance_requirement_loop!(message)
      question = DiscoveryFollowupQuestion.find_by(consultant_info_request_id: @request.id)
      return unless question

      ConsultantRequirements::RecordAnswerService.call(question: question, message: message)
    rescue StandardError => e
      Rails.logger.error(
        "[ConsultantFollowup::RecordReply] request=#{@request.id} #{e.class}: #{e.message}"
      )
    end
  end
end
