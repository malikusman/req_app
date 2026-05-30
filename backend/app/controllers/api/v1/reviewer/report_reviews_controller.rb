# frozen_string_literal: true

module Api
  module V1
    module Reviewer
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
        end

        def mark_ready
          authorize @review, :mark_ready?
          ReportReviews::MarkReadyService.call(
            report_review: @review,
            note: params[:ready_note]
          )
          render json: review_payload(@review.reload)
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def request_regeneration
          authorize @review, :submit?
          report = Reports::RegenerateFromReviewService.call(
            source_report: @report,
            requested_by: current_reviewer_user,
            note: params[:note].presence || @review.overall_note
          )
          render json: { ok: true, report_id: report.id, report_version: report.version }, status: :accepted
        end

        private

        def load_report
          @report = policy_scope(::Report).find(params[:report_id])
        end

        def load_review
          @review = ReportReview.find_by!(report: @report, reviewer_user: current_reviewer_user)
        end

        def review_params
          params.permit(:status, :overall_note)
        end

        def review_payload(review)
          co_reviews = @report.report_reviews.includes(:reviewer_user).where.not(id: review.id)
          {
            review: {
              id: review.id,
              status: review.status,
              sign_off_status: review.sign_off_status,
              overall_note: review.overall_note,
              ready_at: review.ready_at,
              ready_note: review.ready_note,
              submitted_at: review.submitted_at,
              section_states: review.report_review_section_states.map { |s| { section_key: s.section_key, status: s.status } },
              comments: review.report_review_comments.order(:created_at).map { |c| comment_json(c) }
            },
            co_reviewer_reviews: co_reviews.map do |cr|
              {
                reviewer_user_id: cr.reviewer_user_id,
                reviewer_name: cr.reviewer_user.name,
                status: cr.status,
                sign_off_status: cr.sign_off_status,
                ready_at: cr.ready_at,
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
            reviewer_user_id: c.reviewer_user_id,
            reviewer_name: c.reviewer_user.name,
            created_at: c.created_at
          }
        end
      end
    end
  end
end
