# frozen_string_literal: true

class EmployeeWebSession < ApplicationRecord
  belongs_to :employee
  belongs_to :company

  validates :token_digest, :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }

  def expired?
    expires_at.past?
  end

  def verified?
    verified_at.present?
  end

  def touch_seen!(ip_address: nil)
    update!(last_seen_at: Time.current, ip_address: ip_address.presence || self.ip_address)
  end
end
