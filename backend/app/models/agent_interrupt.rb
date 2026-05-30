# frozen_string_literal: true

class AgentInterrupt < ApplicationRecord
  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true

  KINDS = %w[discovery_reply report_section opportunity_recommendation].freeze
  STATUSES = %w[pending approved rejected edited].freeze

  validates :thread_id, :kind, :status, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
end
