# frozen_string_literal: true

class ReportReviewSectionState < ApplicationRecord
  belongs_to :report_review

  STATUSES = %w[pending approved needs_info].freeze

  validates :section_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :section_key, uniqueness: { scope: :report_review_id }
end
