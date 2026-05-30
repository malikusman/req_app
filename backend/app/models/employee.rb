# frozen_string_literal: true

class Employee < ApplicationRecord
  belongs_to :company
  belongs_to :invited_by_company_user, class_name: "CompanyUser", optional: true
  has_many :employee_access_codes, dependent: :destroy
  has_many :employee_invitations, dependent: :destroy
  has_many :employee_nudges, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :conversation_insights, dependent: :destroy
  has_many :media_attachments, dependent: :destroy
  has_many :documents, dependent: :nullify

  PARTICIPATION_STATUSES = %w[invited started completed declined].freeze
  ONBOARDING_STEPS = %w[awaiting_name awaiting_company awaiting_company_join_code awaiting_access_code awaiting_consent verified].freeze

  validates :phone_e164, uniqueness: true, allow_nil: true
  validates :email, uniqueness: true, allow_nil: true
  validates :participation_status, inclusion: { in: PARTICIPATION_STATUSES }
  validates :onboarding_step, inclusion: { in: ONBOARDING_STEPS }
  validate :phone_or_email_present

  private

  def phone_or_email_present
    return if phone_e164.present? || email.present?

    errors.add(:base, "Either phone or email is required")
  end
end
