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
  ONBOARDING_STEPS = %w[awaiting_name awaiting_company awaiting_access_code awaiting_consent verified].freeze

  validates :phone_e164, presence: true, uniqueness: true
  validates :participation_status, inclusion: { in: PARTICIPATION_STATUSES }
  validates :onboarding_step, inclusion: { in: ONBOARDING_STEPS }
end
