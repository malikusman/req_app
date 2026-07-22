# frozen_string_literal: true

# Self-serve company account request awaiting platform approval (FEAT-SIGNUP).
class CompanyRegistration < ApplicationRecord
  belongs_to :company
  belongs_to :company_user
  belongs_to :reviewed_by_platform_user, class_name: "PlatformUser", optional: true

  STATUSES = %w[pending approved rejected].freeze

  validates :company_name, :admin_name, :admin_email, presence: true
  validates :admin_email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }

  before_validation :normalize_email

  def pending?
    status == "pending"
  end

  private

  def normalize_email
    self.admin_email = admin_email.to_s.strip.downcase.presence
  end
end
