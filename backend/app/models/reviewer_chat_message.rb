# frozen_string_literal: true

class ReviewerChatMessage < ApplicationRecord
  belongs_to :company
  belongs_to :sender_reviewer_user, class_name: "ReviewerUser", optional: true
  belongs_to :sender_platform_user, class_name: "PlatformUser", optional: true

  SENDER_ROLES = %w[reviewer platform].freeze

  validates :sender_role, inclusion: { in: SENDER_ROLES }
  validate :sender_presence

  def sender_name
    return sender_reviewer_user&.name if sender_role == "reviewer"
    return sender_platform_user&.name if sender_role == "platform"

    "Unknown"
  end

  private

  def sender_presence
    if sender_role == "reviewer" && sender_reviewer_user_id.blank?
      errors.add(:sender_reviewer_user, "must exist")
    end
    if sender_role == "platform" && sender_platform_user_id.blank?
      errors.add(:sender_platform_user, "must exist")
    end
  end
end
