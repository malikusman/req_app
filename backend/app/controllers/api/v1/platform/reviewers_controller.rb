# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReviewersController < BaseController
        def index
          reviewers = policy_scope(ReviewerUser).order(:name)
          render json: { reviewers: reviewers.map { |r| reviewer_json(r) } }
        end

        def show
          reviewer = ReviewerUser.find(params[:id])
          authorize reviewer, :show?
          render json: { reviewer: reviewer_json(reviewer, detailed: true) }
        end

        def create
          reviewer = ReviewerUser.new(reviewer_params.merge(status: "active", password: params.dig(:reviewer, :password)))
          authorize reviewer, :create?
          reviewer.save!
          render json: { reviewer: reviewer_json(reviewer) }, status: :created
        end

        def update
          reviewer = ReviewerUser.find(params[:id])
          authorize reviewer, :update?
          reviewer.update!(reviewer_params)
          if params[:password].present?
            reviewer.update!(password: params[:password])
            reviewer.regenerate_jti!
          end
          render json: { reviewer: reviewer_json(reviewer) }
        end

        private

        def reviewer_params
          params.require(:reviewer).permit(:email, :name, :status)
        end

        def reviewer_json(reviewer, detailed: false)
          json = {
            id: reviewer.id,
            email: reviewer.email,
            name: reviewer.name,
            status: reviewer.status
          }
          if detailed
            json[:assignments] = reviewer.reviewer_assignments.active.includes(:company).map do |a|
              { company_id: a.company_id, company_name: a.company.display_name || a.company.name }
            end
          end
          json
        end
      end
    end
  end
end
