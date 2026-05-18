# frozen_string_literal: true

class ReviewerAssignment < ApplicationRecord
  belongs_to :reviewer_user
  belongs_to :company
  belongs_to :assigned_by_platform_user, class_name: "PlatformUser"

  STATUSES = %w[active removed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :assigned_at, presence: true

  scope :active, -> { where(status: "active") }

  def remove!
    update!(status: "removed", removed_at: Time.current)
  end
end
