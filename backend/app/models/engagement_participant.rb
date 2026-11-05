# frozen_string_literal: true

# Someone the client plans to involve (Doc 07 §7): staff for discovery (P3) or
# another manager to speak with (P4). Becomes linked to an Employee once invited.
#
# The key user takes part in the conversations with leadership too, so they get a
# KEY_PERSON row of their own (source KEY_USER, linked to their CompanyUser). It
# isn't part of the plan they edit, so the planning screens leave it out.
class EngagementParticipant < ApplicationRecord
  belongs_to :engagement
  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :company_user, optional: true

  PARTICIPANT_TYPES = %w[EMPLOYEE KEY_PERSON].freeze
  # KEY_PERSON_CONVERSATION: someone the key user confirmed during their
  # conversation with leadership (Doc 08 §13).
  SOURCES = %w[ONBOARDING CONSULTANT KEY_USER KEY_PERSON_CONVERSATION].freeze
  # Doc 08 §3. Doc 06 §3.6 lists fewer; the extra functional heads are weighted as
  # department heads (Doc 08 §8.2).
  PERSONAS = %w[CEO_OWNER_MD GM_COO DEPARTMENT_HEAD CFO_FINANCE SALES_COMMERCIAL PROCUREMENT_SUPPLY MARKETING
                OPERATIONS CUSTOMER_SERVICE HR IT_DIGITAL OTHER].freeze
  # Doc 06 §3.6, plus NOT_INVITED for someone planned but not yet asked.
  PARTICIPATION_STATUSES = %w[NOT_INVITED INVITED STARTED PAUSED COMPLETED ABANDONED DECLINED].freeze

  validates :participant_type, inclusion: { in: PARTICIPANT_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :persona, inclusion: { in: PERSONAS }, allow_nil: true
  validates :participation_status, inclusion: { in: PARTICIPATION_STATUSES }
  validates :name, presence: true, length: { maximum: 120 }
  validates :role_title, :department, :scope, length: { maximum: 120 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone_e164, uniqueness: { scope: :engagement_id }, allow_nil: true
  validate :company_matches_engagement

  scope :employees, -> { where(participant_type: "EMPLOYEE") }
  scope :key_persons, -> { where(participant_type: "KEY_PERSON") }
  # The plan as the key user sees and edits it: everyone but themselves.
  scope :planned, -> { where.not(source: "KEY_USER") }

  def key_user? = source == "KEY_USER"

  private

  def company_matches_engagement
    errors.add(:company, "must be the engagement's company") if engagement && company_id != engagement.company_id
  end
end
