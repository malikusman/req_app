# frozen_string_literal: true

module Reviewers
  class CoReviewerActivity
    SECTION_ACTIVE = %w[approved needs_info].freeze
    REVIEWING_STATUSES = %w[in_review needs_info].freeze

    def self.call(review:, company_id:)
      new(review: review, company_id: company_id).call
    end

    def initialize(review:, company_id:)
      @review = review
      @company_id = company_id
    end

    def call
      chat_count = ReviewerChatMessage.where(
        company_id: @company_id,
        sender_reviewer_user_id: @review.reviewer_user_id
      ).count
      comment_count = @review.report_review_comments.count
      sections_touched = @review.report_review_section_states.count { |s| SECTION_ACTIVE.include?(s.status) }
      last_chat = ReviewerChatMessage.where(
        company_id: @company_id,
        sender_reviewer_user_id: @review.reviewer_user_id
      ).maximum(:created_at)
      last_comment = @review.report_review_comments.maximum(:created_at)
      last_active_at = [last_chat, last_comment, @review.updated_at].compact.max

      {
        activity: compute_activity(chat_count, comment_count, sections_touched),
        activity_detail: build_detail(chat_count, comment_count, sections_touched),
        chat_message_count: chat_count,
        comment_count: comment_count,
        sections_touched: sections_touched,
        last_active_at: last_active_at
      }
    end

    private

    def compute_activity(chat_count, comment_count, sections_touched)
      return "submitted" if @review.submitted_at.present?
      if REVIEWING_STATUSES.include?(@review.status) || sections_touched.positive? || comment_count.positive?
        return "reviewing"
      end
      return "discussing" if chat_count.positive?

      "not_started"
    end

    def build_detail(chat_count, comment_count, sections_touched)
      parts = []
      parts << "#{chat_count} chat #{'message'.pluralize(chat_count)}" if chat_count.positive?
      parts << "#{comment_count} section #{'note'.pluralize(comment_count)}" if comment_count.positive?
      if sections_touched.positive?
        parts << "#{sections_touched} section#{'s' unless sections_touched == 1} reviewed"
      end
      parts.empty? ? "No activity yet" : parts.join(" · ")
    end
  end
end
