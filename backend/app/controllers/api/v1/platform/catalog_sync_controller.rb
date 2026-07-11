# frozen_string_literal: true

module Api
  module V1
    module Platform
      class CatalogSyncController < BaseController
        def create
          CatalogSyncAllSourcesJob.perform_later
          render json: { status: "enqueued" }, status: :accepted
        end
      end
    end
  end
end
