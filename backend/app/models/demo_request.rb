# frozen_string_literal: true

# A demo/access request captured from the public marketing site.
class DemoRequest < ApplicationRecord
  STATUSES = %w[new contacted closed].freeze

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, length: { maximum: 200 },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :company_name, presence: true, length: { maximum: 200 }
  validates :role, length: { maximum: 120 }, allow_blank: true
  validates :notes, length: { maximum: 2000 }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
end
