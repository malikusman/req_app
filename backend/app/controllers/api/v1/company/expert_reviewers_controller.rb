# frozen_string_literal: true

module Api
  module V1
    module Company
      class ExpertReviewersController < BaseController
        def index
          reviewers = current_company.reviewer_assignments.active
            .includes(:reviewer_user)
            .map(&:reviewer_user)
            .select(&:published_profile?)

          render json: {
            expert_reviewers: reviewers.map { |r| Reviewers::ProfileSerializer.public_card(r, request: request) }
          }
        end
      end
    end
  end
end
