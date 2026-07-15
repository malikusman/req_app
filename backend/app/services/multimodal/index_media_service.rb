# frozen_string_literal: true

module Multimodal
  # Persists WhatsApp media extraction as a company Document + vector chunks so
  # later discovery turns can retrieve it via ContextBuilder (same path as portal uploads).
  class IndexMediaService
    def self.call(media_attachment:)
      new(media_attachment: media_attachment).call
    end

    def initialize(media_attachment:)
      @attachment = media_attachment
      @message = media_attachment.message
      @employee = media_attachment.employee
      @company = media_attachment.company
      @conversation = media_attachment.conversation
    end

    def call
      return nil unless indexing_enabled?
      return nil unless @attachment.status == "ready"
      return @attachment.document if @attachment.document_id.present?

      text = combined_text
      return nil if text.blank?
      return nil if @attachment.storage_key.blank?

      document = Document.find_by(message_id: @message.id)
      unless document
        document = @company.documents.create!(
          employee: @employee,
          conversation: @conversation,
          message: @message,
          source: @message.channel == "web" ? "web_upload" : "whatsapp_upload",
          department: @employee.department.presence,
          filename: filename_for_attachment,
          content_type: @attachment.mime_type,
          byte_size: byte_size_for_attachment,
          storage_key: @attachment.storage_key,
          status: "processing",
          metadata: {
            "media_attachment_id" => @attachment.id,
            "attachment_type" => @attachment.attachment_type
          }
        )
      end

      chunk_count = ChunkEmbedder.call(document: document, text: text)
      preview = build_insights_preview(text, chunk_count)

      document.update!(
        status: "ready",
        insights_preview: preview,
        processing_error: nil
      )

      @attachment.update!(document: document)
      AggregateIntelligenceJob.perform_later(@company.id, @employee.department)

      document
    rescue StandardError => e
      Rails.logger.error("[IndexMediaService] failed attachment=#{@attachment.id}: #{e.message}")
      document&.update!(status: "failed", processing_error: e.message) if document&.persisted?
      nil
    end

    private

    def indexing_enabled?
      @company.merged_settings["discovery_media_indexing_enabled"] == true
    end

    def combined_text
      [@attachment.caption, @attachment.extracted_text].map(&:presence).compact.join("\n\n")
    end

    def filename_for_attachment
      meta_name = @attachment.metadata["filename"].presence
      return meta_name if meta_name.present?

      ext = extension_for_type
      "whatsapp-#{@attachment.attachment_type}-#{@attachment.id}#{ext}"
    end

    def extension_for_type
      case @attachment.attachment_type
      when "audio" then ".ogg"
      when "image" then ".jpg"
      when "document" then ".pdf"
      else ".bin"
      end
    end

    def byte_size_for_attachment
      @attachment.metadata.fetch("byte_size", 0).to_i
    end

    def build_insights_preview(text, chunk_count)
      structured = @attachment.structured_insights.presence || {}
      {
        "summary" => structured["summary"].presence || text.truncate(500),
        "chunk_count" => chunk_count,
        "source" => (@message.channel == "web" ? "web_upload" : "whatsapp_upload"),
        "media_type" => @attachment.attachment_type,
        "confidence" => @attachment.confidence,
        "tools" => structured["tools_visible"] || structured["tools_mentioned"],
        "pain_points" => structured["pain_points"] || structured["friction_points"]
      }.compact
    end
  end
end
