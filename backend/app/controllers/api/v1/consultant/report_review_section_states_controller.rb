# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ReportReviewSectionStatesController < BaseController
        before_action :load_review

        def update
          authorize @review, :update?
          # A review opened before a section existed has no row for it; a current
          # section gets one on first judgement, a retired one is still a 404.
          states = @review.report_review_section_states
          state = if ReportSections::KEYS.include?(params[:section_key])
                    states.find_or_create_by!(section_key: params[:section_key])
                  else
                    states.find_by!(section_key: params[:section_key])
                  end
          state.update!(status: params.require(:status))
          @review.update!(status: "in_review") if @review.status == "pending"
          report = @review.report
          if report.review_workflow_status == "awaiting_consultants"
            report.update!(review_workflow_status: "in_review")
          end
          render json: { section_state: { section_key: state.section_key, status: state.status } }
        end

        private

        def load_review
          report = policy_scope(::Report).find(params[:report_id])
          @review = ReportReview.find_by!(report: report, consultant_user: current_consultant_user)
        end
      end
    end
  end
end
