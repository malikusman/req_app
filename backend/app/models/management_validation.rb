# frozen_string_literal: true

# Whether what staff describe bears out one of leadership's strategic findings
# (Doc 10 §15, Doc 08 §15 validation_need and §20, P11 management_versus_evidence).
# Both accounts are kept; a material difference is itself a finding, worded
# for the client only once a consultant approves it (Doc 15 §8.4).
class ManagementValidation < ApplicationRecord
  include SynthesisVersioned
  version_key :strategic_finding_id

  SCHEMA_VERSION = "MV.v1"
  RELATIONSHIPS = %w[SUPPORTED PARTLY_SUPPORTED NOT_YET_OBSERVED POINTS_ELSEWHERE].freeze
  # RESOLVED: the consultant settled a difference, with a reason. CLARIFY: they
  # want it asked about before it goes anywhere.
  STATUSES = %w[PROPOSED APPROVED RESOLVED CLARIFY REJECTED SUPERSEDED].freeze
  ORIGINS = %w[AI CONSULTANT].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :synthesis_run, optional: true
  belongs_to :strategic_finding

  validates :management_view, presence: true
  validates :relationship, inclusion: { in: RELATIONSHIPS }
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }

  scope :approved, -> { where(status: %w[APPROVED RESOLVED]) }

  # The fact status the difference gives leadership's statement (Doc 06 §2.2).
  def fact_status = relationship == "POINTS_ELSEWHERE" && material ? "CONTRADICTED" : "REPORTED"
end
