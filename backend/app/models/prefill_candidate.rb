# frozen_string_literal: true

# A value read from the client's website and proposed for confirmation (Doc 06
# §3.3). Unconfirmed, it stays INFERRED and nothing downstream reads it: only
# the onboarding screen shows it. Confirming or correcting it writes the company
# profile; a correction keeps the website's value here as evidence.
class PrefillCandidate < ApplicationRecord
  belongs_to :company
  belongs_to :engagement
  belongs_to :decided_by, polymorphic: true, optional: true

  # The onboarding fields a website can reasonably answer (Doc 07 §5.3, P01 §5).
  FIELDS = %w[industry products_services locations business_model customer_channels departments core_systems
              ai_tools].freeze
  STATUSES = %w[PROPOSED CONFIRMED CORRECTED REJECTED].freeze
  CONFIDENCES = %w[HIGH MEDIUM LOW].freeze

  validates :target_field, inclusion: { in: FIELDS }
  validates :status, inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :source_url, :evidence_excerpt, :website_url, :prompt_version, :extracted_at, presence: true

  scope :proposed, -> { where(status: "PROPOSED") }
  scope :decided, -> { where.not(status: "PROPOSED") }

  def fact_status = status == "PROPOSED" || status == "REJECTED" ? "INFERRED" : "REPORTED"
end
