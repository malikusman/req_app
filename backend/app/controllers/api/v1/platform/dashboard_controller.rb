# frozen_string_literal: true

module Api
  module V1
    module Platform
      class DashboardController < BaseController
        def show
          render json: Dashboard::PlatformSummary.call
        end
      end
    end
  end
end
