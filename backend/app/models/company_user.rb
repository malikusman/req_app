# frozen_string_literal: true

class CompanyUser < ApplicationRecord
  has_secure_password
  belongs_to :company
  belongs_to :invited_by, class_name: "CompanyUser", optional: true

  ROLES = %w[company_admin company_viewer].freeze
  STATUSES = %w[pending active deactivated].freeze

  validates :email, presence: true, uniqueness: { scope: :company_id }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  before_create :ensure_jti
  before_validation :normalize_email

  def company_admin?
    role == "company_admin"
  end

  def regenerate_jti!
    update!(jti: SecureRandom.uuid)
  end

  def issue_password_reset_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(
      password_reset_token_digest: Digest::SHA256.hexdigest(token),
      password_reset_sent_at: Time.current
    )
    token
  end

  def password_reset_token_valid?(token)
    return false if password_reset_token_digest.blank? || password_reset_sent_at.blank?
    return false if password_reset_sent_at < 30.minutes.ago

    ActiveSupport::SecurityUtils.secure_compare(password_reset_token_digest, Digest::SHA256.hexdigest(token.to_s))
  end

  def clear_password_reset_token!
    update!(password_reset_token_digest: nil, password_reset_sent_at: nil)
  end

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end

  def normalize_email
    self.email = email.to_s.downcase.strip
  end
end
