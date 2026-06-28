# frozen_string_literal: true

class ReviewDiscussion < ApplicationRecord
  TARGET_TYPES = %w[reviewer employee].freeze
  ANCHOR_TYPES = %w[message finding section].freeze
  STATUSES = %w[open resolved].freeze

  belongs_to :report
  belongs_to :company
  belongs_to :author_reviewer_user, class_name: "ReviewerUser"
  belongs_to :target_reviewer_user, class_name: "ReviewerUser", optional: true
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :parent, class_name: "ReviewDiscussion", optional: true

  has_many :replies, class_name: "ReviewDiscussion", foreign_key: :parent_id, dependent: :destroy
  has_one :reviewer_info_request, dependent: :nullify

  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :anchor_type, inclusion: { in: ANCHOR_TYPES }
  validates :anchor_id, presence: true
  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :target_presence

  scope :roots, -> { where(parent_id: nil) }
  scope :open, -> { where(status: "open") }

  private

  def target_presence
    if target_type == "reviewer" && target_reviewer_user_id.blank?
      errors.add(:target_reviewer_user_id, "is required for reviewer questions")
    end
    if target_type == "employee" && employee_id.blank?
      errors.add(:employee_id, "is required for employee questions")
    end
  end
end
