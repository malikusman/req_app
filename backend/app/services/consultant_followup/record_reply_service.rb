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
    # The employee answered a question someone asked them; saying nothing back is
    # worse than it sounds. Before this, an answer to a consultant landed in silence
    # while a casual "thanks!" got a warm companion reply -- so the one message that
    # took real effort was the one that looked ignored.
    #
    # Worded by outcome, because "we're done" and "there may be more" are different
    # promises. Deliberately no channel switch: an answer that arrived on WhatsApp is
    # acknowledged on WhatsApp (the session window is open by definition -- they just
    # messaged us, so no template is involved), and a web/email answer is
    # acknowledged in the thread they replied into rather than by another email.
    ACK = {
      "satisfied" => {
        "en" => "Thanks — that answers it. Nothing further needed for now.",
        "es" => "Gracias — con eso queda resuelto. Nada más por ahora.",
        "fr" => "Merci — c'est répondu. Rien d'autre pour le moment.",
        "de" => "Danke — damit ist es geklärt. Vorerst nichts weiter."
      },
      "more_coming" => {
        "en" => "Thanks — that helps. There may be one more quick question on this.",
        "es" => "Gracias — eso ayuda. Puede haber otra pregunta rápida sobre esto.",
        "fr" => "Merci — c'est utile. Il y aura peut-être une dernière question.",
        "de" => "Danke — das hilft. Vielleicht kommt noch eine kurze Frage dazu."
      },
      "recorded" => {
        "en" => "Thanks — I've passed that on.",
        "es" => "Gracias — ya lo he transmitido.",
        "fr" => "Merci — je l'ai transmis.",
        "de" => "Danke — ich habe es weitergegeben."
      }
    }.freeze

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

      question = advance_requirement_loop!(message)
      acknowledge!(question)
      message
    end

    private

    # Never raises: the answer is recorded and the consultant already notified by
    # this point, so a failed courtesy message must not undo any of that.
    def acknowledge!(question)
      body = ACK.fetch(ack_kind(question)).then { |t| t[language] || t["en"] }

      outbound = @request.conversation.messages.create!(
        direction: "outbound",
        message_type: "text",
        channel: @channel == "whatsapp" ? "whatsapp" : "web",
        body: body,
        is_discovery_question: false,
        track: "consultant_followup",
        track_ref: @request,
        raw_payload: { "kind" => "consultant_followup_ack" }
      )

      return outbound unless @channel == "whatsapp"

      client = Whatsapp::MetaClient.new
      if client.configured?
        response = client.send_text(to: @request.employee.phone_e164, body: body)
        outbound.update(external_id: response&.dig("messages", 0, "id"))
      else
        Rails.logger.info("[ConsultantFollowup::Ack dev] to=#{@request.employee.phone_e164} body=#{body}")
      end
      outbound
    rescue StandardError => e
      Rails.logger.warn("[ConsultantFollowup::Ack] request=#{@request.id} #{e.class}: #{e.message}")
      nil
    end

    # A requirement that is still open means the consultant may well ask again, so
    # promising "nothing further" would be a lie. No requirement at all is the legacy
    # standalone-request path, where we genuinely cannot say what happens next.
    def ack_kind(question)
      requirement = question&.consultant_requirement
      return "recorded" unless requirement

      requirement.reload.status == "satisfied" ? "satisfied" : "more_coming"
    end

    def language
      (@request.employee.preferred_language.presence ||
        @request.company.locale.presence || "en").to_s
    end

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
    #
    # Returns the question (when there was one) so the acknowledgement can be worded
    # from the resulting requirement status rather than guessing.
    def advance_requirement_loop!(message)
      question = DiscoveryFollowupQuestion.find_by(consultant_info_request_id: @request.id)
      return nil unless question

      ConsultantRequirements::RecordAnswerService.call(question: question, message: message)
      question
    rescue StandardError => e
      Rails.logger.error(
        "[ConsultantFollowup::RecordReply] request=#{@request.id} #{e.class}: #{e.message}"
      )
      # The evaluation failed, so we cannot claim the need is settled -- but the
      # answer IS recorded, and the employee should still hear that much.
      question
    end
  end
end
