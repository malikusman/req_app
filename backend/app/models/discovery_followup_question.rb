# frozen_string_literal: true

# A question the agent intends to ask next, drafted from what the interview parked
# or from what a consultant said they need to know.
#
# The consultant sees these, reorders them, and skips them — but never writes the
# text. That is the point of the object: one stated need can produce several
# questions, and the agent has to know when the need is satisfied.
class DiscoveryFollowupQuestion < ApplicationRecord
  belongs_to :discovery_package
  # Null means the agent drafted it from a parked aside; set means it was drafted
  # from a consultant's stated need.
  belongs_to :consultant_requirement, optional: true
  # The channel the question actually went out on. This link is what lets an
  # inbound reply find the question it answers.
  belongs_to :consultant_info_request, optional: true
  belongs_to :sent_message, class_name: "Message", optional: true
  belongs_to :answered_message, class_name: "Message", optional: true

  STATUSES = %w[drafted queued sent answered skipped superseded].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :body, presence: true

  scope :pending, -> { where(status: %w[drafted queued]) }
  scope :in_queue_order, -> { order(:queue_position, :id) }

  def answered?
    status == "answered"
  end

  def from_parked_aside?
    source_parked_ref.present?
  end

  def from_consultant_need?
    consultant_requirement_id.present?
  end
end
