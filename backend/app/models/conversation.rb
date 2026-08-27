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

  # The interview ceiling for THIS conversation. A reopen (addendum) raises it,
  # otherwise it comes from Discovery::ContextBuilder's resolution chain
  # (company setting -> ENV -> default).
  def max_questions
    stored = state_snapshot["max_questions"]
    return stored.to_i if stored.present?

    Discovery::ContextBuilder.limits_for(company)[:max_questions]
  end

  # Legacy single-agent path (multi_agent disabled) still runs on a fixed target.
  def effective_question_target
    stored = state_snapshot["question_target"]
    return stored.to_i if stored.present?

    company.merged_settings.fetch("discovery_question_target", 10).to_i
  end

  def close_reason
    blackboard["close_reason"]
  end

  def dossier
    state_snapshot.dig("blackboard", "dossier") || { "slots" => {}, "parked" => [] }
  end

  def blackboard
    state_snapshot["blackboard"] || {}
  end

  def update_blackboard!(updates)
    update!(state_snapshot: state_snapshot.merge("blackboard" => blackboard.merge(updates)))
  end
end
