# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ReviewDiscussionsController < BaseController
        before_action :set_report

        def index
          authorize ReviewDiscussion.new(report: @report, company: @report.company), :index?

          discussions = policy_scope(::ReviewDiscussion)
                         .where(report_id: @report.id)
                         .includes(:author_consultant_user, :target_consultant_user, :replies)
                         .order(:created_at)

          render json: { discussions: discussions.roots.map { |d| discussion_json(d) } }
        end

        def create
          discussion = ReviewDiscussions::CreateService.call(
            consultant: current_consultant_user,
            report: @report,
            params: discussion_params
          )
          authorize discussion
          render json: { discussion: discussion_json(discussion) }, status: :created
        end

        def reply
          parent = policy_scope(::ReviewDiscussion).find(params[:id])
          authorize parent, :reply?

          discussion = ReviewDiscussions::CreateService.call(
            consultant: current_consultant_user,
            report: @report,
            params: discussion_params.merge(
              parent_id: parent.id,
              target_type: parent.target_type,
              target_consultant_user_id: parent.target_consultant_user_id,
              employee_id: parent.employee_id,
              conversation_id: parent.conversation_id,
              anchor_type: parent.anchor_type,
              anchor_id: parent.anchor_id
            )
          )
          render json: { discussion: discussion_json(discussion) }, status: :created
        end

        def resolve
          discussion = policy_scope(::ReviewDiscussion).find(params[:id])
          authorize discussion, :resolve?
          discussion.update!(status: "resolved")
          render json: { discussion: discussion_json(discussion) }
        end

        private

        def set_report
          @report = policy_scope(::Report).find(params[:report_id])
        end

        def discussion_params
          params.permit(
            :target_type,
            :target_consultant_user_id,
            :employee_id,
            :conversation_id,
            :anchor_type,
            :anchor_id,
            :body,
            :message_id
          )
        end

        def discussion_json(discussion)
          {
            id: discussion.id,
            parent_id: discussion.parent_id,
            target_type: discussion.target_type,
            target_consultant_user_id: discussion.target_consultant_user_id,
            target_consultant_name: discussion.target_consultant_user&.name,
            employee_id: discussion.employee_id,
            conversation_id: discussion.conversation_id,
            anchor_type: discussion.anchor_type,
            anchor_id: discussion.anchor_id,
            body: discussion.body,
            status: discussion.status,
            author_consultant_user_id: discussion.author_consultant_user_id,
            author_name: discussion.author_consultant_user.name,
            created_at: discussion.created_at,
            replies: discussion.replies.order(:created_at).map { |r| discussion_json(r) }
          }
        end
      end
    end
  end
end
