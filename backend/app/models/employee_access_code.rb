# frozen_string_literal: true

class EmployeeAccessCode < ApplicationRecord
  belongs_to :employee
  belongs_to :company

  STATUSES = %w[active used revoked expired].freeze

  validates :code_digest, :expires_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }

  def self.generate_plain_code
    SecureRandom.alphanumeric(8).upcase
  end

  def self.issue_for!(employee:, issued_by_type: "system")
    plain = generate_plain_code
    employee.employee_access_codes.active.update_all(status: "revoked", revoked_at: Time.current)
    code = employee.employee_access_codes.create!(
      company: employee.company,
      code_digest: BCrypt::Password.create(plain),
      code_hint_last_two: plain.last(2),
      expires_at: 14.days.from_now,
      issued_by_type: issued_by_type,
      status: "active"
    )
    [code, plain]
  end

  def verify(plain)
    return false unless status == "active" && expires_at.future?

    BCrypt::Password.new(code_digest) == plain
  end
end
