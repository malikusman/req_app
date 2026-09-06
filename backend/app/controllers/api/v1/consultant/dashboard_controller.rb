# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class DashboardController < BaseController
        def show
          companies = policy_scope(::Company)
            .includes(:subscription, :consultant_assignments, reports: [])
            .order(:name)

          render json: Dashboard::ConsultantSummary.call(
            consultant_user: current_consultant_user,
            companies: companies
          )
        end
      end
    end
  end
end
