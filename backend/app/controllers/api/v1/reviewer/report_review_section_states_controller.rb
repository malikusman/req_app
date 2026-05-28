# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ReportReviewSectionStatesController < BaseController
        before_action :load_review

        def update
          state = @review.report_review_section_states.find_by!(section_key: params[:section_key])
          authorize @review, :update?
          state.update!(status: normalize_section_status(params.require(:status)))
          @review.update!(status: "in_review") if @review.status == "pending"
          render json: { section_state: { section_key: state.section_key, status: state.status } }
        end

        private

        def load_review
          report = policy_scope(::Report).find(params[:report_id])
          @review = ReportReview.find_by!(report: report, reviewer_user: current_reviewer_user)
        end

        def normalize_section_status(raw)
          {
            "not_started" => "pending",
            "in_progress" => "pending",
            "reviewed" => "approved",
            "needs_clarification" => "needs_info"
          }.fetch(raw.to_s, raw.to_s)
        end
      end
    end
  end
end
