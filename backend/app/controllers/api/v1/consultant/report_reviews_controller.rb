# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ReportReviewsController < BaseController
        before_action :load_report
        before_action :load_review

        def show
          authorize @review, :show?
          render json: review_payload(@review)
        end

        def update
          authorize @review, :update?
          @review.update!(review_params)
          render json: review_payload(@review.reload)
        end

        def submit
          authorize @review, :submit?
          ReportReviews::SubmitService.call(report_review: @review)
          render json: review_payload(@review.reload)
        rescue ReportReviews::SubmitService::IncompleteReviewError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def load_report
          @report = policy_scope(::Report).find(params[:report_id])
        end

        def load_review
          @review = ReportReview.find_by!(report: @report, consultant_user: current_consultant_user)
        end

        def review_params
          params.permit(:status, :overall_note, :opportunity_amount, :opportunity_unit, :opportunity_basis)
        end

        def review_payload(review)
          co_reviews = @report.report_reviews.includes(:consultant_user).where.not(id: review.id)
          {
            review: {
              id: review.id,
              status: review.status,
              overall_note: review.overall_note,
              opportunity_amount: review.opportunity_amount,
              opportunity_unit: review.opportunity_unit,
              opportunity_basis: review.opportunity_basis,
              submitted_at: review.submitted_at,
              section_states: review.report_review_section_states.map { |s| { section_key: s.section_key, status: s.status } },
              comments: review.report_review_comments.order(:created_at).map { |c| comment_json(c) }
            },
            co_consultant_reviews: co_reviews.map do |cr|
              {
                consultant_user_id: cr.consultant_user_id,
                consultant_name: cr.consultant_user.name,
                status: cr.status,
                submitted_at: cr.submitted_at,
                section_states: cr.report_review_section_states.map { |s| { section_key: s.section_key, status: s.status } },
                comments: cr.report_review_comments.order(:created_at).map { |c| comment_json(c) }
              }
            end
          }
        end

        def comment_json(c)
          {
            id: c.id,
            section_key: c.section_key,
            body: c.body,
            resolved: c.resolved,
            consultant_user_id: c.consultant_user_id,
            consultant_name: c.consultant_user.name,
            created_at: c.created_at
          }
        end
      end
    end
  end
end
