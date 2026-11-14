# frozen_string_literal: true

# Benchmark loaded cost of a client role's hour, by role family and market. Never
# client salary data. Versioned, and the version used is disclosed in the report.
class BenchmarkRate < ApplicationRecord
  validates :version, :market, :role_family, :currency, :effective_from, presence: true
  validates :hourly_rate_min, :hourly_rate_max, numericality: { greater_than: 0 }
  validate :range_is_ordered

  scope :active, -> { where(active: true) }

  # The newest active rate for a role family, or nil — in which case callers show
  # hours and no currency, rather than inventing a value.
  def self.for(role_family, market: "AE")
    active.where(market: market, role_family: role_family.to_s.downcase)
          .where("effective_from <= ?", Date.current)
          .order(effective_from: :desc, id: :desc)
          .first
  end

  private

  def range_is_ordered
    return if hourly_rate_min.blank? || hourly_rate_max.blank?

    errors.add(:hourly_rate_max, "must be at least the minimum") if hourly_rate_max < hourly_rate_min
  end
end
