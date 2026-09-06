# frozen_string_literal: true

# Reviewer -> Consultant.
#
# A reviewer checks AI output; a consultant exercises judgement. The rename is a
# change in meaning, so it reaches the schema rather than stopping at UI copy.
#
# Deliberately NOT renamed:
#   - report_reviews, report_review_comments, report_review_findings,
#     report_section_overrides, review_discussions. "Review" is the act and the
#     artifact; "consultant" is the actor. A consultant performs a review.
#   - The Meta-registered WhatsApp template name (external, needs re-approval).
#
# Safe as a single transactional migration because the app deploys to one host
# (scripts/deploy/deploy.sh over ssh), so two app versions never serve at once.
# Client-side compatibility (JWT claims, stored browser sessions) is handled in
# the application layer, not here.
class RenameReviewerToConsultant < ActiveRecord::Migration[7.1]
  TABLES = {
    reviewer_users: :consultant_users,
    reviewer_assignments: :consultant_assignments,
    reviewer_chat_messages: :consultant_chat_messages,
    reviewer_experiences: :consultant_experiences,
    reviewer_info_requests: :consultant_info_requests,
    reviewer_info_replies: :consultant_info_replies,
    reviewer_outreaches: :consultant_outreaches,
    reviewer_outreach_replies: :consultant_outreach_replies
  }.freeze

  # [table, old_column, new_column] — evaluated after the table renames above.
  COLUMNS = [
    [:catalog_endorsements, :reviewer_user_id, :consultant_user_id],
    [:company_catalog_matches, :added_by_reviewer_id, :added_by_consultant_id],
    [:company_clarification_questions, :dismissed_by_reviewer_user_id, :dismissed_by_consultant_user_id],
    [:documents, :reviewer_visible, :consultant_visible],
    [:messages, :reviewer_followup, :consultant_followup],
    [:report_review_comments, :reviewer_user_id, :consultant_user_id],
    [:report_review_findings, :reviewer_user_id, :consultant_user_id],
    [:report_reviews, :reviewer_user_id, :consultant_user_id],
    [:report_section_overrides, :reviewer_user_id, :consultant_user_id],
    [:review_discussions, :author_reviewer_user_id, :author_consultant_user_id],
    [:review_discussions, :target_reviewer_user_id, :target_consultant_user_id],
    [:consultant_assignments, :reviewer_user_id, :consultant_user_id],
    [:consultant_chat_messages, :sender_reviewer_user_id, :sender_consultant_user_id],
    [:consultant_experiences, :reviewer_user_id, :consultant_user_id],
    [:consultant_info_replies, :reviewer_info_request_id, :consultant_info_request_id],
    [:consultant_info_requests, :reviewer_user_id, :consultant_user_id],
    [:consultant_outreaches, :reviewer_user_id, :consultant_user_id],
    [:consultant_outreaches, :reviewer_info_request_id, :consultant_info_request_id],
    [:consultant_outreach_replies, :reviewer_outreach_id, :consultant_outreach_id]
  ].freeze

  def up
    TABLES.each { |old, new| rename_table old, new }
    COLUMNS.each { |table, old, new| rename_column table, old, new }
    rename_index :consultant_assignments,
                 "index_reviewer_assignments_active_unique",
                 "index_consultant_assignments_active_unique"
    rename_index :consultant_info_requests,
                 "index_reviewer_info_requests_awaiting_reply",
                 "index_consultant_info_requests_awaiting_reply"

    # Stored string values that name the actor.
    execute("UPDATE agentic_ideas SET source = 'consultant' WHERE source = 'reviewer'")
  end

  def down
    execute("UPDATE agentic_ideas SET source = 'reviewer' WHERE source = 'consultant'")

    rename_index :consultant_info_requests,
                 "index_consultant_info_requests_awaiting_reply",
                 "index_reviewer_info_requests_awaiting_reply"
    rename_index :consultant_assignments,
                 "index_consultant_assignments_active_unique",
                 "index_reviewer_assignments_active_unique"
    COLUMNS.reverse_each { |table, old, new| rename_column table, new, old }
    TABLES.each { |old, new| rename_table new, old }
  end
end
