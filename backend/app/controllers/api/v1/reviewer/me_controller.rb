# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class MeController < BaseController
        def show
          render json: {
            user: {
              id: current_reviewer_user.id,
              email: current_reviewer_user.email,
              name: current_reviewer_user.name
            },
            assignments: policy_scope(::ReviewerAssignment).active.includes(:company).map do |a|
              {
                company_id: a.company_id,
                company_name: a.company.display_name || a.company.name,
                assigned_at: a.assigned_at
              }
            end
          }
        end
      end
    end
  end
end
