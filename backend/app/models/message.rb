# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation
  has_one :media_attachment, dependent: :destroy
  has_one :document, dependent: :nullify
  has_one :discovery_question_feedback, dependent: :destroy

  DIRECTIONS = %w[inbound outbound].freeze
  TYPES = %w[text audio image document interactive system].freeze
  PROCESSING_STATUSES = %w[pending processing ready failed].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :message_type, inclusion: { in: TYPES }
  validates :processing_status, inclusion: { in: PROCESSING_STATUSES }

  scope :discovery_only, -> { where(reviewer_followup: false) }
  scope :reviewer_followup_only, -> { where(reviewer_followup: true) }
end
