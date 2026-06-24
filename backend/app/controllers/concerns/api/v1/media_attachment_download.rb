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

        stream_attachment(attachment)
      end

      private

      def stream_attachment(attachment, retried: false)
        data = Storage::MinioClient.new.download(attachment.storage_key)
        disposition = %w[image audio].include?(attachment.attachment_type) ? "inline" : "attachment"
        filename = Multimodal::MediaAttachmentSerializer.filename_for(attachment)

        send_data data,
                  filename: filename,
                  type: attachment.mime_type.presence || "application/octet-stream",
                  disposition: disposition
      rescue Aws::S3::Errors::NoSuchKey
        if !retried && backfill_missing_storage!(attachment)
          stream_attachment(attachment.reload, retried: true)
        else
          render json: { error: "Media not found" }, status: :not_found
        end
      end

      def backfill_missing_storage!(attachment)
        refetched = try_meta_refetch!(attachment)
        return true if refetched

        try_dev_backfill!(attachment)
      end

      def try_meta_refetch!(attachment)
        return false unless attachment.meta_media_id.present?
        return false unless Whatsapp::MetaClient.new.configured?

        Multimodal::MetaMediaFetcher.new.fetch_and_store!(media_attachment: attachment)
        true
      rescue StandardError => e
        Rails.logger.warn("[MediaDownload] meta refetch failed attachment=#{attachment.id}: #{e.message}")
        false
      end

      def try_dev_backfill!(attachment)
        return false unless dev_backfill_allowed?(attachment)

        Multimodal::DevStorageBackfill.call(attachment)
        true
      rescue StandardError => e
        Rails.logger.warn("[MediaDownload] dev backfill failed attachment=#{attachment.id}: #{e.message}")
        false
      end

      def dev_backfill_allowed?(attachment)
        return true if dev_simulated_key?(attachment.storage_key)
        return true if Rails.env.development? || Rails.env.test?

        Multimodal::DevStorageBackfill.fixture_available?(attachment)
      end

      def dev_simulated_key?(storage_key)
        storage_key.to_s.start_with?("dev/simulated/")
      end

      def verify_media_attachment_company!(_attachment)
        nil
      end
    end
  end
end
