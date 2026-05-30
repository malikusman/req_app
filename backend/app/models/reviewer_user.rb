# frozen_string_literal: true

class ReviewerUser < ApplicationRecord
  include ReviewerProfileable

  has_secure_password

  has_many :reviewer_assignments, dependent: :destroy
  has_many :companies, through: :reviewer_assignments
  has_many :report_reviews, dependent: :destroy
  has_many :notifications, as: :recipient, dependent: :destroy

  STATUSES = %w[active deactivated].freeze

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  before_create :ensure_jti
  before_validation :normalize_email

  scope :active, -> { where(status: "active") }

  def active_company_ids
    reviewer_assignments.active.pluck(:company_id)
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
