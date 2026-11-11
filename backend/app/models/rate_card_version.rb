# frozen_string_literal: true

# Mjadi's own delivery rates and the Stage 1 formula's values (Doc 06 §10.3,
# Doc 17 §2.3, §7). INTERNAL_COMMERCIAL: never in a client view, a client
# output or any model context but pricing's (Doc 05 §4.2).
#
# Rates are by skill and delivery source, each with an internal cost and a
# charge rate (Doc 17 §7.2); Stage 1 uses the consultant's. `stage1` holds the
# fee components, the hours and costs behind them, and the quote's terms.
#
# Never edited: a change is a new version, with who made it and why.
class RateCardVersion < ApplicationRecord
  # Every value Stage 1 pricing reads. A version without one of them can't be
  # saved; Pricing::Stage1Calculator checks again, since the tax rate depends
  # on the client's country (Doc 17 §17).
  STAGE1_NUMBERS = %w[
    base_fee per_participant_fee per_deep_dive_fee additional_participant_rate
    complexity.per_extra_language complexity.per_extra_location complexity.departments_threshold
    complexity.per_department_over_threshold
    hours.base hours.per_participant hours.per_deep_dive hours.per_key_person hours.per_extra_language
    hours.per_extra_location
    ai_cost.per_participant ai_cost.per_deep_dive ai_cost.per_key_person
    platform_allocation licences deep_dives.min deep_dives.max validity_days
  ].freeze

  belongs_to :changed_by, polymorphic: true, optional: true

  validates :version, presence: true, uniqueness: true
  validates :effective_from, :currency, :reason, presence: true
  validate :stage1_complete

  def self.current(at = Time.current)
    where(effective_from: ..at).order(version: :desc).first
  end

  def self.next_version = (maximum(:version) || 0) + 1

  def readonly? = persisted?

  def stage1_value(path) = stage1.dig(*path.split("."))

  def consultant_internal_cost = rates.dig("consultant", "mjadi_team", "internal_cost")

  private

  def stage1_complete
    missing = STAGE1_NUMBERS.reject { |path| numeric?(stage1_value(path)) }
    missing << "consultant internal cost" unless numeric?(consultant_internal_cost)
    errors.add(:stage1, "needs a number for #{missing.join(', ')}") if missing.any?
    return if stage1["tax_rates"].is_a?(Hash) && stage1["tax_rates"].values.all? { |v| numeric?(v) }

    errors.add(:stage1, "needs tax rates by country")
  end

  def numeric?(value) = value.is_a?(Numeric) && value >= 0
end
