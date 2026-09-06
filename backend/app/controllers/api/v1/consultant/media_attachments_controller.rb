# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class MediaAttachmentsController < BaseController
        include Api::V1::MediaAttachmentDownload
        include Api::V1::MediaAttachmentIndex

        private

        def media_namespace
          :consultant
        end

        def verify_media_attachment_company!(attachment)
          return nil if attachment.company_id == params[:company_id].to_i

          render json: { error: "Not found" }, status: :not_found
          :not_found
        end
      end
    end
  end
end
