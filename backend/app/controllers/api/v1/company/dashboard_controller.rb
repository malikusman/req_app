# frozen_string_literal: true

module Api
  module V1
    module Company
      class DashboardController < BaseController
        def show
          render json: Dashboard::CompanySummary.call(
            company: current_company,
            company_user: current_company_user,
            impersonating: impersonating?,
            impersonation_session: impersonation_session
          )
        end
      end
    end
  end
end
