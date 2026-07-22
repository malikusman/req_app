# frozen_string_literal: true

class CompanyUser < ApplicationRecord
  has_secure_password
  belongs_to :company
  belongs_to :invited_by, class_name: "CompanyUser", optional: true
  has_one :company_registration, dependent: :nullify

  ROLES = %w[company_admin company_viewer].freeze
  STATUSES = %w[pending active deactivated].freeze

  validates :email, presence: true, uniqueness: { scope: :company_id }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }

  before_create :ensure_jti

  def company_admin?
    role == "company_admin"
  end

  def regenerate_jti!
    update!(jti: SecureRandom.uuid)
  end

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end
end
