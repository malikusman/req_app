# frozen_string_literal: true

# One underlying problem behind several symptoms (Doc 10 §13, Doc 06 §6.6).
# Always INFERRED until a consultant confirms it; a low-confidence one never
# becomes a recommendation without review.
class RootCause < ApplicationRecord
  include SynthesisVersioned
  version_key :root_cause_key

  SCHEMA_VERSION = "RC.v1"
  STATUSES = %w[PROPOSED APPROVED REJECTED SUPERSEDED].freeze
  FACT_STATUSES = %w[INFERRED CONSULTANT_CONFIRMED].freeze
  CONFIDENCES = %w[HIGH MEDIUM LOW].freeze
  ORIGINS = %w[AI CONSULTANT].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :synthesis_run, optional: true

  validates :root_cause_key, :statement, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :fact_status, inclusion: { in: FACT_STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :origin, inclusion: { in: ORIGINS }

  scope :approved, -> { where(status: "APPROVED") }
end
