# frozen_string_literal: true

class ReviewerInfoRequest < ApplicationRecord
  belongs_to :company
  belongs_to :report, optional: true
  belongs_to :reviewer_user
  belongs_to :employee
  belongs_to :conversation

  has_many :reviewer_info_replies, dependent: :destroy

  STATUSES = %w[draft sent awaiting_reply replied closed failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :body, presence: true

  scope :awaiting_reply, -> { where(status: "awaiting_reply") }

  def self.open_for_employee(employee_id)
    awaiting_reply.where(employee_id: employee_id).order(created_at: :desc).first
  end
end
