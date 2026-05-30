# frozen_string_literal: true

module Api
  module V1
    module Company
      class ExpertReviewersController < BaseController
        def index
          assigned_reviewers = current_company.reviewer_assignments.active
            .includes(:reviewer_user)
            .map(&:reviewer_user)
          reviewers = assigned_reviewers.select(&:published_profile?)
          pending_review_count = assigned_reviewers.count { |r| r.profile_status == "pending_review" }

          render json: {
            expert_reviewers: reviewers.map { |r| Reviewers::ProfileSerializer.public_card(r, request: request) },
            pending_review_count: pending_review_count
          }
        end
      end
    end
  end
end
