# frozen_string_literal: true

class ReportReviewFinding < ApplicationRecord
  belongs_to :report_review
  belongs_to :reviewer_user

  FINDING_TYPES = %w[
    executive_conclusion evidence_sufficiency correction risk recommendation_disposition
    catalog_assessment unresolved_followup addendum endorsement
  ].freeze
  DISPOSITIONS = %w[endorse modify reject needs_more_evidence approve needs_info none].freeze
  SEVERITIES = %w[info material critical].freeze

  validates :finding_type, inclusion: { in: FINDING_TYPES }
  validates :body, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :disposition, inclusion: { in: DISPOSITIONS }, allow_nil: true

  scope :publishable, -> { where(publishable: true) }

  def publishable?
    publishable
  end
end
