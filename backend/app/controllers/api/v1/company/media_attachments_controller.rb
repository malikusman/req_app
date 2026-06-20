# frozen_string_literal: true

module Api
  module V1
    module Company
      class MediaAttachmentsController < BaseController
        include Api::V1::MediaAttachmentDownload
        include Api::V1::MediaAttachmentIndex

        private

        def media_namespace
          :company
        end
      end
    end
  end
end
