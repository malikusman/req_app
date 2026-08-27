# frozen_string_literal: true

module Multimodal
  module MediaAttachmentSerializer
    module_function

    def call(attachment, request:, namespace:, company_id: nil)
      {
        id: attachment.id,
        message_id: attachment.message_id,
        attachment_type: attachment.attachment_type,
        mime_type: attachment.mime_type,
        status: attachment.status,
        caption: attachment.caption,
        confidence: attachment.confidence,
        duration_ms: attachment.duration_ms,
        language: attachment.language,
        structured_insights: safe_insights(attachment),
        processing_error: attachment.processing_error,
        document_id: attachment.document_id,
        filename: filename_for(attachment),
        download_url: download_path(attachment, request: request, namespace: namespace, company_id: company_id),
        created_at: attachment.created_at,
        updated_at: attachment.updated_at
      }
    end

    def download_path(attachment, request:, namespace:, company_id: nil)
      return nil if request.nil? || attachment.storage_key.blank? || attachment.status != "ready"

      base = request.base_url
      case namespace
      when :company
        "#{base}/api/v1/company/media_attachments/#{attachment.id}/download"
      when :platform
        cid = company_id || attachment.company_id
        "#{base}/api/v1/platform/companies/#{cid}/media_attachments/#{attachment.id}/download"
      when :consultant
        cid = company_id || attachment.company_id
        "#{base}/api/v1/consultant/companies/#{cid}/media_attachments/#{attachment.id}/download"
      else
        nil
      end
    end

    def safe_insights(attachment)
      (attachment.structured_insights.presence || {}).except("raw_excerpt")
    end

    def filename_for(attachment)
      attachment.metadata["filename"].presence ||
        "whatsapp-#{attachment.attachment_type}-#{attachment.id}#{extension_for(attachment)}"
    end

    def extension_for(attachment)
      case attachment.attachment_type
      when "audio" then ".ogg"
      when "image" then ".jpg"
      when "document" then ".pdf"
      else ".bin"
      end
    end
  end
end
