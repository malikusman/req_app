# frozen_string_literal: true

# What Discovery hands the consultant: a recommendation, the issues found, possible
# solutions, and the questions the agent intends to ask next.
#
# One current package per conversation. An addendum reopen mints the next version
# and supersedes the previous one, carrying the consultant's edits forward — the
# same pattern as Reports::GenerateReportService#carry_forward_overrides!, and for
# the same reason: without it a consultant's amendments vanish when an employee adds
# one more thought.
class DiscoveryPackage < ApplicationRecord
  belongs_to :conversation
  belongs_to :employee
  belongs_to :company

  has_many :discovery_package_items, dependent: :destroy
  has_many :discovery_followup_questions, dependent: :destroy

  STATUSES = %w[generating ready consultant_reviewed failed superseded].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :version, presence: true, uniqueness: { scope: :conversation_id }

  scope :current, -> { where.not(status: "superseded") }
  scope :ready, -> { where(status: %w[ready consultant_reviewed]) }

  def issues
    discovery_package_items.where(kind: "issue").order(:ordinal, :id)
  end

  def solutions
    discovery_package_items.where(kind: "solution").order(:ordinal, :id)
  end

  # Position 1 is the question that goes out next.
  def queued_followups
    discovery_followup_questions.where(status: %w[drafted queued]).order(:queue_position, :id)
  end

  def next_followup
    queued_followups.first
  end

  def built_without_model?
    generated_by == "deterministic"
  end
end
