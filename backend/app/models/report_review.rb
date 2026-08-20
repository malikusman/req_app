# frozen_string_literal: true

class ReportReview < ApplicationRecord
  belongs_to :report
  belongs_to :reviewer_user
  belongs_to :company

  has_many :report_review_section_states, dependent: :destroy
  has_many :report_review_comments, dependent: :destroy
  has_many :report_review_findings, dependent: :destroy

  # A review is approved, or flagged needs_info (which requests changes and blocks
  # platform approval). "rejected" was never selectable and is intentionally dropped.
  STATUSES = %w[pending in_review needs_info approved].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :reviewer_user_id, uniqueness: { scope: :report_id }

  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :pending_submit, -> { where(submitted_at: nil) }

  def submitted?
    submitted_at.present?
  end
  # NOTE: submission goes through ReportReviews::SubmitService, which enforces
  # completeness (all sections decided, overall note, needs_info comments). The
  # old bypassing #submit! was removed so there's a single, validated submit path.
end
