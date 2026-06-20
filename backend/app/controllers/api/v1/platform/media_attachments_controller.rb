# frozen_string_literal: true

module Api
  module V1
    module Platform
      class MediaAttachmentsController < BaseController
        include Api::V1::MediaAttachmentDownload

        private

        def verify_media_attachment_company!(attachment)
          return nil if attachment.company_id == params[:company_id].to_i

          render json: { error: "Not found" }, status: :not_found
          :not_found
        end
      end
    end
  end
end
