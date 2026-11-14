# frozen_string_literal: true

# An administrator changing a proposed price, or issuing one below the margin
# floor (Doc 06 §10.11, Doc 17 §8.3, §9.2–9.3). The structured reason is how the
# pricing model learns where it is wrong (§13), so it can't be saved without
# one. INTERNAL_COMMERCIAL. Kept as written.
class EstimateOverride < ApplicationRecord
  KINDS = %w[ADJUST FLOOR_OVERRIDE].freeze
  # Doc 17 §9.3, which adds BUNDLE to Doc 06's list.
  REASONS = %w[RELATIONSHIP COMPETITIVE COMPLEXITY_UNDER COMPLEXITY_OVER DELIVERY_SOURCE SCOPE_CLARIFICATION BUNDLE
               OTHER].freeze

  belongs_to :quote
  belongs_to :actor, class_name: "PlatformUser"

  validates :kind, inclusion: { in: KINDS }
  validates :structured_reason, inclusion: { in: REASONS, message: "is required" }
  validates :free_text, presence: { message: "is required when the reason is Other" }, if: -> { structured_reason == "OTHER" }
  validates :original_total, :adjusted_total, presence: true

  def readonly? = persisted?
end
