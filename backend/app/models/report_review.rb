# frozen_string_literal: true

class ReportReview < ApplicationRecord
  belongs_to :report
  belongs_to :reviewer_user
  belongs_to :company

  has_many :report_review_section_states, dependent: :destroy
  has_many :report_review_comments, dependent: :destroy
  has_many :report_review_findings, dependent: :destroy

  STATUSES = %w[pending in_review needs_info approved rejected].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :reviewer_user_id, uniqueness: { scope: :report_id }

  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :pending_submit, -> { where(submitted_at: nil) }

  def submitted?
    submitted_at.present?
  end

  def submit!
    update!(submitted_at: Time.current, status: status == "pending" ? "approved" : status)
  end
end
