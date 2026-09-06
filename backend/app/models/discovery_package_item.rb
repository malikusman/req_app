# frozen_string_literal: true

# An issue the interview surfaced, or a solution proposed for one.
#
# Agent items are never hard-deleted. A consultant rejecting an issue is a signal
# about agent quality, so the row stays with status "rejected" rather than
# disappearing.
class DiscoveryPackageItem < ApplicationRecord
  belongs_to :discovery_package
  belongs_to :linked_item, class_name: "DiscoveryPackageItem", optional: true
  has_many :linked_solutions, class_name: "DiscoveryPackageItem",
                              foreign_key: :linked_item_id, dependent: :nullify,
                              inverse_of: :linked_item

  KINDS = %w[issue solution].freeze
  ORIGINS = %w[agent consultant].freeze
  STATUSES = %w[proposed accepted amended rejected].freeze
  IMPACTS = %w[low medium high].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :origin, inclusion: { in: ORIGINS }
  validates :status, inclusion: { in: STATUSES }
  validates :impact, inclusion: { in: IMPACTS }, allow_nil: true
  validates :body, presence: true

  scope :issues, -> { where(kind: "issue") }
  scope :solutions, -> { where(kind: "solution") }
  scope :live, -> { where.not(status: "rejected") }

  def rejected?
    status == "rejected"
  end
end
