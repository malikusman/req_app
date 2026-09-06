# frozen_string_literal: true

class PlatformUser < ApplicationRecord
  has_secure_password
  has_many :platform_audit_logs, dependent: :destroy
  has_many :consultant_assignments, foreign_key: :assigned_by_platform_user_id, dependent: :nullify
  has_many :notifications, as: :recipient, dependent: :destroy

  ROLES = %w[super_admin support analyst].freeze

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  before_create :ensure_jti

  def regenerate_jti!
    update!(jti: SecureRandom.uuid)
  end

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end
end
