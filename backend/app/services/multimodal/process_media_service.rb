# frozen_string_literal: true

module Multimodal
  class ProcessMediaService
    ACK_MESSAGES = {
      "en" => "Got your %{type} — processing it now…",
      "es" => "Recibí tu %{type} — lo estoy procesando…",
      "fr" => "Bien reçu — traitement en cours…",
      "de" => "Erhalten — wird verarbeitet…"
    }.freeze

    TYPE_LABELS = {
      "audio" => { "en" => "voice note", "es" => "nota de voz" },
      "image" => { "en" => "image", "es" => "imagen" },
      "document" => { "en" => "document", "es" => "documento" }
    }.freeze

    def self.call(media_attachment_id)
      new(media_attachment_id).call
    end

    def initialize(media_attachment_id)
      @attachment = MediaAttachment.find(media_attachment_id)
      @message = @attachment.message
      @employee = @attachment.employee
      @conversation = @attachment.conversation
      @openai = Openai::Client.new
      @fetcher = MetaMediaFetcher.new
    end

    def call
      @attachment.update!(status: "processing")
      @message.update!(processing_status: "processing")

      file = download_media_file
      extracted = extract_content(file)
      file.close
      file.unlink

      @attachment.update!(status: "ready", extracted_text: extracted)
      @message.update!(
        body: extracted,
        processing_status: "ready",
        raw_payload: @message.raw_payload.merge("extracted_text" => extracted)
      )

      mark_multimodal_on_conversation!
      ContinueDiscoveryAfterMediaJob.perform_later(@attachment.id)
      extracted
    rescue StandardError => e
      @attachment.update!(status: "failed", processing_error: e.message)
      @message.update!(processing_status: "failed")
      Rails.logger.error("[Multimodal] failed attachment=#{@attachment.id}: #{e.message}")
      raise
    end

    private

    def download_media_file
      if @attachment.storage_key.present?
        data = Storage::MinioClient.new.download(@attachment.storage_key)
        file = Tempfile.new(["media", extension_for_type])
        file.binmode
        file.write(data)
        file.rewind
        file
      elsif @attachment.meta_media_id.present?
        @fetcher.fetch_and_store!(media_attachment: @attachment)
        file = Tempfile.new(["media", extension_for_type])
        file.binmode
        file.write(Storage::MinioClient.new.download(@attachment.storage_key))
        file.rewind
        file
      else
        raise "no media source"
      end
    end

    def extract_content(file)
      lang = @employee.preferred_language.presence || @employee.company.locale
      case @attachment.attachment_type
      when "audio"
        @openai.transcribe_audio(file_path: file.path, language: lang)
      when "image"
        @openai.describe_image(file_path: file.path, language: lang)
      when "document"
        text = DocumentTextExtractor.extract(file_path: file.path, content_type: @attachment.mime_type)
        text.presence || @openai.describe_image(file_path: file.path, language: lang)
      else
        ""
      end
    end

    def extension_for_type
      {
        "audio" => ".ogg",
        "image" => ".jpg",
        "document" => ".pdf"
      }.fetch(@attachment.attachment_type, ".bin")
    end

    def mark_multimodal_on_conversation!
      @conversation.update!(
        state_snapshot: @conversation.state_snapshot.merge("had_multimodal" => true)
      )
    end
  end
end
