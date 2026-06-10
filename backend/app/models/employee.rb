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
  SENIORITY_LEVELS = %w[individual_contributor team_lead manager director executive].freeze

  validates :phone_e164, presence: true, uniqueness: true
  validates :participation_status, inclusion: { in: PARTICIPATION_STATUSES }
  validates :onboarding_step, inclusion: { in: ONBOARDING_STEPS }
  validates :seniority, inclusion: { in: SENIORITY_LEVELS }, allow_nil: true

  def profile_data
    metadata["profile"] || {}
  end

  def profile_complete?
    role_title.present? && seniority.present? && profile_data["responsibilities"].present?
  end

  def manager_or_above?
    %w[manager director executive].include?(seniority)
  end

  def profile_card
    {
      "employee_id" => id,
      "name" => display_name,
      "department" => department.presence || "default",
      "role_title" => role_title,
      "seniority" => seniority,
      "responsibilities" => profile_data["responsibilities"],
      "team_size" => profile_data["team_size"],
      "primary_tools" => profile_data["primary_tools"] || [],
      "preferred_language" => preferred_language
    }
  end
end
