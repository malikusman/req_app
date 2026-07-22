# frozen_string_literal: true

class Conversation < ApplicationRecord
  belongs_to :employee
  belongs_to :company
  has_many :messages, dependent: :destroy
  has_many :conversation_insights, dependent: :destroy
  has_many :media_attachments, dependent: :destroy
  has_many :documents, dependent: :nullify
  has_many :employee_nudges, dependent: :nullify

  STATUSES = %w[onboarding profiling discovery completed abandoned].freeze

  validates :status, inclusion: { in: STATUSES }

  def touch_activity!
    update!(last_activity_at: Time.current)
  end

  def discovery?
    status == "discovery"
  end

  def profiling?
    status == "profiling"
  end

  def completed?
    status == "completed"
  end

  def effective_question_target
    stored = state_snapshot["question_target"]
    return stored.to_i if stored.present?

    company.merged_settings.fetch("discovery_question_target", 10).to_i
  end

  def blackboard
    state_snapshot["blackboard"] || {}
  end

  def update_blackboard!(updates)
    update!(state_snapshot: state_snapshot.merge("blackboard" => blackboard.merge(updates)))
  end
end
