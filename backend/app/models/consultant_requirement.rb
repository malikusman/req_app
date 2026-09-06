# frozen_string_literal: true

# What a consultant needs to know, in their own words.
#
# They state the need; the agent drafts the questions. That separation is the point:
# one need can take several questions to satisfy, and something has to hold the
# answer to "is this settled yet?" across them.
class ConsultantRequirement < ApplicationRecord
  belongs_to :consultant_user
  belongs_to :discovery_package
  belongs_to :employee
  belongs_to :company

  has_many :discovery_followup_questions, dependent: :nullify

  STATUSES = %w[open questions_drafted partially_satisfied satisfied withdrawn].freeze
  BASES = %w[agent_judged consultant_manual].freeze
  OPEN_STATUSES = %w[open questions_drafted partially_satisfied].freeze

  validates :statement, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :satisfaction_basis, inclusion: { in: BASES }, allow_nil: true

  scope :open_requirements, -> { where(status: OPEN_STATUSES) }
  scope :satisfied, -> { where(status: "satisfied") }

  def open?
    OPEN_STATUSES.include?(status)
  end

  def satisfied?
    status == "satisfied"
  end

  def questions_asked
    discovery_followup_questions.where(status: %w[sent answered]).count
  end

  # A budget is spent by questions actually put to the employee, not by drafts a
  # consultant discarded.
  def budget_remaining
    [max_questions - questions_asked, 0].max
  end

  def budget_exhausted?
    budget_remaining.zero?
  end

  def answers
    discovery_followup_questions
      .where(status: "answered")
      .includes(:answered_message)
      .order(:queue_position, :id)
      .filter_map { |q| { question: q.body, answer: q.answered_message&.body } if q.answered_message }
  end

  def satisfy!(basis:, missing: [])
    update!(
      status: "satisfied",
      satisfaction_basis: basis,
      satisfied_at: Time.current,
      missing_aspects: missing
    )
  end
end
