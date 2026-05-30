# frozen_string_literal: true

class CompanyInfoRequest < ApplicationRecord
  belongs_to :company
  belongs_to :requested_by, polymorphic: true
  has_many :company_info_request_replies, dependent: :destroy

  STATUSES = %w[open answered closed].freeze

  validates :subject, :body, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :profile_section_valid

  scope :open_status, -> { where(status: "open") }
  scope :recent_first, -> { order(created_at: :desc) }

  def requested_by_name
    case requested_by_type
    when "ReviewerUser" then requested_by&.name
    when "PlatformUser" then requested_by&.name
    else "Unknown"
    end
  end

  def requested_by_role_label
    requested_by_type == "PlatformUser" ? "Platform" : "Expert reviewer"
  end

  private

  def profile_section_valid
    return if profile_section.blank?
    allowed = Companies::ProfileContextSchema::ALL_SECTIONS + %w[documents]
    return if allowed.include?(profile_section)

    errors.add(:profile_section, "is invalid")
  end
end
