# frozen_string_literal: true

class Report < ApplicationRecord
  belongs_to :company
  belongs_to :previous_report, class_name: "Report", optional: true
  belongs_to :reviewed_by_platform_user, class_name: "PlatformUser", optional: true
  has_many :report_share_accesses, dependent: :destroy
  has_many :report_reviews, dependent: :destroy

  STATUSES = %w[queued generating ready failed].freeze
  VISIBILITIES = %w[internal_only shared_with_company].freeze
  REVIEW_WORKFLOW_STATUSES = %w[
    not_required awaiting_reviewers in_review reviews_complete platform_approved
  ].freeze

  validates :version, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :version, uniqueness: { scope: :company_id }

  scope :ready, -> { where(status: "ready") }

  def share_active?
    share_token.present? && share_token_expires_at.present? && share_token_expires_at.future?
  end

  def next_version_for_company
    (company.reports.maximum(:version) || 0) + 1
  end
end
