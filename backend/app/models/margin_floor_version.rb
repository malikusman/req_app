# frozen_string_literal: true

# The minimum gross margin a quote may be issued at without an administrator's
# override (Doc 06 §10.4, Doc 17 §8, Decision Register B12). Versioned, with who
# changed it, when and why: a floor that can be lowered without trace is not a
# control (§8.3). INTERNAL_COMMERCIAL.
class MarginFloorVersion < ApplicationRecord
  belongs_to :changed_by, polymorphic: true, optional: true

  validates :version, presence: true, uniqueness: true
  validates :effective_from, :reason, presence: true
  validates :value, numericality: { greater_than: 0, less_than: 1 }

  def self.current(at = Time.current)
    where(effective_from: ..at).order(version: :desc).first
  end

  def self.next_version = (maximum(:version) || 0) + 1

  def readonly? = persisted?

  def percent = (value * 100).round(2)
end
