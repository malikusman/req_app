# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ReportReviewCommentsController < BaseController
        before_action :load_review

        def index
          authorize @review, :show?
          comments = @review.report_review_comments.order(:created_at)
          render json: { comments: comments.map { |c| comment_json(c) } }
        end

        def create
          comment = @review.report_review_comments.build(comment_params.merge(consultant_user: current_consultant_user))
          authorize comment, :create?
          comment.save!
          notify_co_consultant(comment)
          render json: { comment: comment_json(comment) }, status: :created
        end

        def update
          comment = @review.report_review_comments.find(params[:id])
          authorize comment, :update?
          comment.update!(comment_params)
          render json: { comment: comment_json(comment) }
        end

        def destroy
          comment = @review.report_review_comments.find(params[:id])
          authorize comment, :destroy?
          comment.destroy!
          head :no_content
        end

        private

        def load_review
          report = policy_scope(::Report).find(params[:report_id])
          @review = ReportReview.find_by!(report: report, consultant_user: current_consultant_user)
        end

        def comment_params
          params.require(:comment).permit(:section_key, :body, :resolved)
        end

        def comment_json(c)
          {
            id: c.id,
            section_key: c.section_key,
            body: c.body,
            resolved: c.resolved,
            consultant_user_id: c.consultant_user_id,
            created_at: c.created_at
          }
        end

        def notify_co_consultant(comment)
          company = @review.company
          other_ids = company.consultant_assignments.active.pluck(:consultant_user_id) - [current_consultant_user.id]
          ConsultantUser.where(id: other_ids).find_each do |consultant|
            NotificationService.notify_co_consultant_commented(
              consultant: consultant,
              company: company,
              report: @review.report
            )
          end
        end
      end
    end
  end
end
