# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class DashboardController < BaseController
        def show
          companies = policy_scope(::Company)
            .includes(:subscription, :reviewer_assignments, reports: [])
            .order(:name)

          render json: Dashboard::ReviewerSummary.call(
            reviewer_user: current_reviewer_user,
            companies: companies
          )
        end
      end
    end
  end
end
