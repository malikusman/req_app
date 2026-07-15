# frozen_string_literal: true

class EmployeeValuePreference < ApplicationRecord
  belongs_to :employee

  FREQUENCIES = %w[monthly twice_monthly].freeze
  validates :frequency, inclusion: { in: FREQUENCIES }

  scope :opted_in, -> { where(email_opt_in: true).where(unsubscribed_at: nil) }

  def subscribed?
    email_opt_in && unsubscribed_at.blank?
  end

  def opted_in?
    subscribed?
  end
end
