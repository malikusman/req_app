# frozen_string_literal: true

class InsightTimelineEvent < ApplicationRecord
  belongs_to :company

  EVENT_TYPES = %w[
    signal_detected
    pattern_detected
    signal_strengthened
    interview_completed
    conversation_reopened
  ].freeze

  validates :event_type, :title, :occurred_at, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
end
