# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ReviewWorkspaceController < BaseController
        include Api::V1::MediaAttachmentJson
        include Api::V1::DiscoveryConversationJson

        def show
          report = policy_scope(::Report).find(params[:id])
          authorize report, :show?

          review = ReportReview.find_by!(report: report, reviewer_user: current_reviewer_user)
          authorize review, :show?

          company = report.company
          conversations = policy_scope(::Conversation)
                         .where(company_id: company.id)
                         .includes(:employee)
                         .order(updated_at: :desc)

          render json: {
            company: {
              id: company.id,
              name: company.display_name || company.name
            },
            report: report_json(report),
            review: review_json(review),
            co_reviewer_reviews: co_reviewer_reviews_json(report, review),
            discussions: discussions_json(report),
            conversations: conversations.map { |c| conversation_json(c) }
          }
        end

        private

        def report_json(report)
          {
            id: report.id,
            version: report.version,
            status: report.status,
            review_workflow_status: report.review_workflow_status,
            report_snapshot: report.report_snapshot,
            generated_at: report.generated_at,
            storage_key: report.storage_key.present?
          }
        end

        def review_json(review)
          {
            id: review.id,
            status: review.status,
            overall_note: review.overall_note,
            submitted_at: review.submitted_at,
            section_states: review.report_review_section_states.map { |s| { section_key: s.section_key, status: s.status } },
            comments: review.report_review_comments.order(:created_at).map { |c| comment_json(c) }
          }
        end

        def co_reviewer_reviews_json(report, review)
          company_id = report.company_id
          report.report_reviews
                .includes(:reviewer_user, :report_review_section_states, :report_review_comments)
                .where.not(id: review.id)
                .map do |cr|
            activity = Reviewers::CoReviewerActivity.call(review: cr, company_id: company_id)
            {
              reviewer_user_id: cr.reviewer_user_id,
              reviewer_name: cr.reviewer_user.name,
              status: cr.status,
              submitted_at: cr.submitted_at,
              section_states: cr.report_review_section_states.map { |s| { section_key: s.section_key, status: s.status } },
              comments: cr.report_review_comments.order(:created_at).map { |c| comment_json(c) }
            }.merge(activity)
          end
        end

        def discussions_json(report)
          ReviewDiscussion
            .where(report_id: report.id)
            .includes(:author_reviewer_user, :target_reviewer_user, :replies)
            .roots
            .order(:created_at)
            .map { |d| discussion_json(d) }
        end

        def discussion_json(discussion)
          {
            id: discussion.id,
            parent_id: discussion.parent_id,
            target_type: discussion.target_type,
            target_reviewer_user_id: discussion.target_reviewer_user_id,
            target_reviewer_name: discussion.target_reviewer_user&.name,
            employee_id: discussion.employee_id,
            conversation_id: discussion.conversation_id,
            anchor_type: discussion.anchor_type,
            anchor_id: discussion.anchor_id,
            body: discussion.body,
            status: discussion.status,
            author_reviewer_user_id: discussion.author_reviewer_user_id,
            author_name: discussion.author_reviewer_user.name,
            created_at: discussion.created_at,
            replies: discussion.replies.order(:created_at).map { |r| discussion_json(r) }
          }
        end

        def comment_json(comment)
          {
            id: comment.id,
            section_key: comment.section_key,
            body: comment.body,
            resolved: comment.resolved,
            reviewer_user_id: comment.reviewer_user_id,
            reviewer_name: comment.reviewer_user.name,
            created_at: comment.created_at
          }
        end

        def conversation_json(conversation)
          employee = conversation.employee
          messages = conversation.messages.includes(:media_attachment).order(:created_at)

          {
            id: conversation.id,
            employee_id: conversation.employee_id,
            employee_name: employee.display_name,
            department: employee.department,
            status: conversation.status,
            question_count: conversation.question_count,
            last_activity_at: conversation.last_activity_at,
            discovery_state: discovery_state_json(conversation, employee),
            discovery_provenance: discovery_provenance_json(messages),
            messages: messages.map { |m| message_json(m, conversation.company_id) },
            media_attachments: media_attachments_json(
              conversation, namespace: :reviewer, company_id: conversation.company_id
            )
          }
        end

        def message_json(message, company_id)
          json = {
            id: message.id,
            direction: message.direction,
            message_type: message.message_type,
            body: message.body,
            reviewer_followup: message.reviewer_followup,
            is_discovery_question: message.is_discovery_question,
            created_at: message.created_at
          }.merge(message_provenance_fields(message))

          if message.media_attachment
            json[:media_attachment] = media_attachment_json(
              message.media_attachment,
              namespace: :reviewer,
              company_id: company_id
            )
          end
          json
        end
      end
    end
  end
end
