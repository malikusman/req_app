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
      attachment_type, meta_media_id, mime_type = extract_media_info
      return send_unsupported_notice unless attachment_type && meta_media_id

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

    def dev_simulate_processing?
      !@client.configured? || ENV["MULTIMODAL_SYNC_DEV"] == "true"
    end

    def simulate_processing!(attachment, message)
      lang = @employee.preferred_language.presence || @company.locale
      openai = Openai::Client.new
      extracted = case attachment.attachment_type
                  when "audio"
                    openai.transcribe_audio(file_path: "/dev/null", language: lang)
                  when "image"
                    openai.describe_image(file_path: "/dev/null", language: lang)
                  else
                    openai.summarize_document("Workflow SOP document", language: lang)["summary"]
                  end

      attachment.update!(status: "ready", extracted_text: extracted, storage_key: "dev/simulated/#{attachment.id}")
      message.update!(body: extracted, processing_status: "ready")
      @conversation.update!(state_snapshot: @conversation.state_snapshot.merge("had_multimodal" => true))
      ContinueDiscoveryAfterMediaJob.perform_now(attachment.id)
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
