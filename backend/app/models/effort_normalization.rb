# frozen_string_literal: true

# What one cluster's work costs, counted twice ways (Doc 10 §10, Doc 06 §6.4):
# the raw sum of every member's own estimate, kept and never overwritten, and
# the de-duplicated active effort every client-facing figure uses. Computed by
# Synthesis::EffortNormalizer, never by a model (Doc 10 §20.2).
#
# A consultant may override the de-duplicated range, with a reason; the
# override wins wherever the figure is read.
class EffortNormalization < ApplicationRecord
  belongs_to :company
  belongs_to :engagement
  belongs_to :process_cluster

  validates :method_version, presence: true
  validate :override_is_coherent

  def hours_min = consultant_min || dedup_min
  def hours_max = consultant_max || dedup_max
  def overridden? = consultant_min.present?
  def hours? = !hours_min.nil? && !hours_max.nil?

  private

  def override_is_coherent
    return if consultant_min.nil? && consultant_max.nil?

    if consultant_min.nil? || consultant_max.nil? || consultant_min.negative? || consultant_min > consultant_max
      errors.add(:consultant_min, "must be a range from zero up")
    end
    errors.add(:override_rationale, "is required for an override") if override_rationale.blank?
  end
end
