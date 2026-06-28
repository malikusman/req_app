# frozen_string_literal: true

module Web
  class MediaInboundService
    class Error < StandardError; end
    class InvalidFile < Error; end
    class FileTooLarge < Error; end

    ALLOWED_TYPES = {
      "image/jpeg" => "image",
      "image/png" => "image",
      "image/webp" => "image",
      "application/pdf" => "document"
    }.freeze

    MAX_BYTES = 10.megabytes
    CHANNEL = "web"

    ACK_MESSAGES = Whatsapp::MultimodalInboundHandler::ACK_MESSAGES

    def self.call(employee:, conversation:, file:, caption: nil)
      new(employee: employee, conversation: conversation, file: file, caption: caption).call
    end

    def initialize(employee:, conversation:, file:, caption: nil)
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @file = file
      @caption = caption.to_s.strip.presence
    end

    def call
      unless allowed_phase?
        send_notice(phase_notice)
        return result_payload
      end

      unless multimodal_enabled?
        send_notice("Please continue with text messages for now.")
        return result_payload
      end

      attachment_type, mime_type = validate_file!

      message = Message.create!(
        conversation: @conversation,
        direction: "inbound",
        channel: CHANNEL,
        message_type: attachment_type,
        body: nil,
        processing_status: "pending"
      )

      attachment = MediaAttachment.create!(
        message: message,
        company: @company,
        employee: @employee,
        conversation: @conversation,
        attachment_type: attachment_type,
        mime_type: mime_type,
        caption: @caption,
        metadata: { "filename" => sanitized_filename },
        status: "pending"
      )

      storage_key = upload_file!(attachment)
      attachment.update!(storage_key: storage_key)

      @conversation.touch_activity!
      send_ack(attachment_type)

      if dev_simulate_processing?
        simulate_processing!(attachment, message)
      else
        ProcessMediaAttachmentJob.perform_later(attachment.id)
      end

      result_payload
    end

    private

    def allowed_phase?
      @conversation.discovery? || @employee.onboarding_step == "verified"
    end

    def phase_notice
      if @conversation.profiling?
        "Please answer with a short text message for now. Once we start the interview you can send voice notes and images."
      else
        "Please complete onboarding with text messages first. After verification you can send voice notes and images."
      end
    end

    def validate_file!
      raise InvalidFile, "No file provided" unless @file.present?

      content_type = @file.content_type.to_s.downcase
      attachment_type = ALLOWED_TYPES[content_type]
      raise InvalidFile, "Unsupported file type" unless attachment_type

      raise FileTooLarge, "File is too large (max 10MB)" if @file.size.to_i > MAX_BYTES

      [attachment_type, content_type]
    end

    def sanitized_filename
      name = @file.original_filename.presence || "upload"
      name.gsub(/[^\w.\-]/, "_")
    end

    def upload_file!(attachment)
      key = "media/#{@company.id}/#{attachment.id}/#{sanitized_filename}"
      Storage::MinioClient.new.upload(
        key: key,
        body: @file.read,
        content_type: attachment.mime_type
      )
      key
    end

    def dev_simulate_processing?
      ENV["MULTIMODAL_SYNC_DEV"] == "true"
    end

    def simulate_processing!(attachment, message)
      lang = @employee.preferred_language.presence || @company.locale
      result = Multimodal::DevUnderstanding.call(attachment: attachment, language: lang)
      body = [attachment.caption, result.plain_text].map(&:presence).compact.join("\n\n")

      attachment.update!(
        status: "ready",
        extracted_text: body,
        structured_insights: result.structured_insights,
        confidence: result.confidence,
        language: lang
      )
      message.update!(body: body, processing_status: "ready")
      mark_multimodal_on_conversation!(attachment)
      Multimodal::MediaObservability.record!(event: "dev_simulated_ready", attachment: attachment)
      Multimodal::IndexMediaService.call(media_attachment: attachment.reload)
      ContinueDiscoveryAfterMediaJob.perform_now(attachment.id)
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
      send_notice(body)
    end

    def send_notice(body)
      Message.create!(
        conversation: @conversation,
        direction: "outbound",
        channel: CHANNEL,
        message_type: "text",
        body: body
      )
    end

    def result_payload
      { employee: @employee.reload, conversation: @conversation.reload }
    end
  end
end
