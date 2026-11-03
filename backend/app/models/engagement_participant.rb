# frozen_string_literal: true

# Someone the client plans to involve (Doc 07 §7): staff for discovery (P3) or
# another manager to speak with (P4). Becomes linked to an Employee once invited.
class EngagementParticipant < ApplicationRecord
  belongs_to :engagement
  belongs_to :company
  belongs_to :employee, optional: true

  PARTICIPANT_TYPES = %w[EMPLOYEE KEY_PERSON].freeze
  SOURCES = %w[ONBOARDING CONSULTANT].freeze

  validates :participant_type, inclusion: { in: PARTICIPANT_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :name, presence: true, length: { maximum: 120 }
  validates :role_title, :department, :scope, length: { maximum: 120 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone_e164, uniqueness: { scope: :engagement_id }, allow_nil: true
  validate :company_matches_engagement

  scope :employees, -> { where(participant_type: "EMPLOYEE") }
  scope :key_persons, -> { where(participant_type: "KEY_PERSON") }

  private

  def company_matches_engagement
    errors.add(:company, "must be the engagement's company") if engagement && company_id != engagement.company_id
  end
end
