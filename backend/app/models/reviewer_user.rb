# frozen_string_literal: true

class ReviewerUser < ApplicationRecord
  has_secure_password

  has_many :reviewer_assignments, dependent: :destroy
  has_many :companies, through: :reviewer_assignments
  has_many :report_reviews, dependent: :destroy
  has_many :notifications, as: :recipient, dependent: :destroy

  STATUSES = %w[active deactivated].freeze

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_create :ensure_jti

  scope :active, -> { where(status: "active") }

  def active_company_ids
    reviewer_assignments.active.pluck(:company_id)
  end

  def regenerate_jti!
    update!(jti: SecureRandom.uuid)
  end

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end
end
