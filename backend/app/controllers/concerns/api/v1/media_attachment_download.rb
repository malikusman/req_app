# frozen_string_literal: true

module Api
  module V1
    module MediaAttachmentDownload
      extend ActiveSupport::Concern

      def download
        attachment = policy_scope(::MediaAttachment).find(params[:id])
        authorize attachment, :download?
        return if verify_media_attachment_company!(attachment) == :not_found

        return render json: { error: "Media not ready" }, status: :not_found unless attachment.status == "ready"
        return render json: { error: "Media unavailable" }, status: :not_found if attachment.storage_key.blank?

        data = Storage::MinioClient.new.download(attachment.storage_key)
        disposition = %w[image audio].include?(attachment.attachment_type) ? "inline" : "attachment"
        filename = Multimodal::MediaAttachmentSerializer.filename_for(attachment)

        send_data data,
                  filename: filename,
                  type: attachment.mime_type.presence || "application/octet-stream",
                  disposition: disposition
      rescue Aws::S3::Errors::NoSuchKey
        render json: { error: "Media not found" }, status: :not_found
      end

      private

      def verify_media_attachment_company!(_attachment)
        nil
      end
    end
  end
end
