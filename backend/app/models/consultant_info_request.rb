# frozen_string_literal: true

class ConsultantInfoRequest < ApplicationRecord
  belongs_to :company
  belongs_to :report, optional: true
  belongs_to :consultant_user
  belongs_to :employee
  belongs_to :conversation

  belongs_to :message, optional: true
  belongs_to :review_discussion, optional: true

  has_many :consultant_info_replies, dependent: :destroy

  STATUSES = %w[draft sent awaiting_reply replied closed failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :body, presence: true

  scope :awaiting_reply, -> { where(status: "awaiting_reply") }

  def self.open_for_employee(employee_id)
    awaiting_reply.where(employee_id: employee_id).order(created_at: :desc).first
  end
end
