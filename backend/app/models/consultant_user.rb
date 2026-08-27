# frozen_string_literal: true

class ConsultantUser < ApplicationRecord
  include ConsultantProfileable

  has_secure_password

  has_many :consultant_assignments, dependent: :destroy
  has_many :companies, through: :consultant_assignments
  has_many :report_reviews, dependent: :destroy
  has_many :notifications, as: :recipient, dependent: :destroy

  STATUSES = %w[pending active deactivated rejected].freeze

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_create :ensure_jti

  scope :active, -> { where(status: "active") }
  scope :pending_applications, -> { where(status: "pending") }

  def active_company_ids
    consultant_assignments.active.pluck(:company_id)
  end

  def regenerate_jti!
    update!(jti: SecureRandom.uuid)
  end

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end
end
