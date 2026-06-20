# frozen_string_literal: true

module Whatsapp
  class MultimodalInboundHandler
    ACK_MESSAGES = {
      "en" => {
        "audio" => "Got your voice note — processing it now…",
        "image" => "Got your image — analyzing it now…",
        "document" => "Got your document — processing it now…"
      },
      "es" => {
        "audio" => "Recibí tu nota de voz — la estoy procesando…",
        "image" => "Recibí tu imagen — la estoy analizando…",
        "document" => "Recibí tu documento — lo estoy procesando…"
      }
    }.freeze

    def initialize(employee:, conversation:, msg:, client: MetaClient.new)
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @msg = msg
      @client = client
    end

    def handle
      unless multimodal_enabled?
        send_text("Please continue with text messages for now.")
        return
      end

      attachment_type, meta_media_id, mime_type = extract_media_info
      return send_unsupported_notice unless attachment_type && meta_media_id

      caption = extract_caption
      metadata = extract_metadata

      message = Message.create!(
        conversation: @conversation,
        direction: "inbound",
        message_type: attachment_type,
        body: nil,
        external_id: @msg["id"],
        processing_status: "pending",
        raw_payload: @msg
      )

      attachment = MediaAttachment.create!(
        message: message,
        company: @company,
        employee: @employee,
        conversation: @conversation,
        attachment_type: attachment_type,
        mime_type: mime_type,
        meta_media_id: meta_media_id,
        caption: caption,
        metadata: metadata,
        status: "pending"
      )

      @conversation.touch_activity!
      send_ack(attachment_type)

      if dev_simulate_processing?
        simulate_processing!(attachment, message)
      else
        ProcessMediaAttachmentJob.perform_later(attachment.id)
      end
    end

    private

    def extract_media_info
      case @msg["type"]
      when "audio"
        ["audio", @msg.dig("audio", "id"), @msg.dig("audio", "mime_type")]
      when "image"
        ["image", @msg.dig("image", "id"), @msg.dig("image", "mime_type")]
      when "document"
        ["document", @msg.dig("document", "id"), @msg.dig("document", "mime_type")]
      end
    end

    def extract_caption
      @msg.dig("image", "caption").presence || @msg.dig("document", "caption").presence
    end

    def extract_metadata
      meta = {}
      meta["filename"] = @msg.dig("document", "filename") if @msg.dig("document", "filename").present?
      meta
    end

    def dev_simulate_processing?
      !@client.configured? || ENV["MULTIMODAL_SYNC_DEV"] == "true"
    end

    def simulate_processing!(attachment, message)
      lang = @employee.preferred_language.presence || @company.locale
      file = nil
      file = Tempfile.new(["dev-media", ".bin"])
      file.write("simulated")
      file.rewind

      result = Multimodal::UnderstandingService.call(attachment: attachment, file_path: file.path)
      body = [attachment.caption, result.plain_text].map(&:presence).compact.join("\n\n")

      attachment.update!(
        status: "ready",
        extracted_text: body,
        structured_insights: result.structured_insights,
        confidence: result.confidence,
        storage_key: "dev/simulated/#{attachment.id}",
        language: lang
      )
      message.update!(body: body, processing_status: "ready")
      mark_multimodal_on_conversation!(attachment)
      Multimodal::MediaObservability.record!(event: "dev_simulated_ready", attachment: attachment)
      Multimodal::IndexMediaService.call(media_attachment: attachment.reload)
      ContinueDiscoveryAfterMediaJob.perform_now(attachment.id)
    ensure
      file&.close
      file&.unlink
    end

    def mark_multimodal_on_conversation!(attachment)
      snapshot = @conversation.state_snapshot.merge("had_multimodal" => true)
      counts = snapshot.fetch("multimodal_counts", { "audio" => 0, "image" => 0, "document" => 0 })
      type = attachment.attachment_type
      counts[type] = counts.fetch(type, 0) + 1 if counts.key?(type)
      snapshot["multimodal_counts"] = counts
      @conversation.update!(state_snapshot: snapshot)
    end

    def multimodal_enabled?
      @company.merged_settings["discovery_multimodal_enabled"] == true
    end

    def send_ack(type)
      lang = @employee.preferred_language.presence || @company.locale
      body = ACK_MESSAGES.fetch(lang, ACK_MESSAGES["en"]).fetch(type) { "Processing your attachment…" }
      send_text(body)
    end

    def send_unsupported_notice
      send_text("I can accept text, voice notes, images, and PDF documents during discovery.")
    end

    def send_text(body)
      Message.create!(
        conversation: @conversation,
        direction: "outbound",
        message_type: "text",
        body: body
      )
      if @client.configured?
        @client.send_text(to: @employee.phone_e164, body: body)
      else
        Rails.logger.info("[WhatsApp dev] to=#{@employee.phone_e164} body=#{body}")
      end
    end
  end
end
