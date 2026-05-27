# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class MeController < BaseController
        def show
          reviewer = current_reviewer_user
          completeness = Reviewers::ProfileCompleteness.call(reviewer)
          render json: {
            user: {
              id: reviewer.id,
              email: reviewer.email,
              name: reviewer.name
            },
            profile: Reviewers::ProfileSerializer.full(reviewer, request: request),
            profile_completeness_percent: completeness.percent,
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
