# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :company, optional: true
  belongs_to :recipient, polymorphic: true

  validates :notification_type, :title, :body, presence: true

  scope :unread, -> { where(read_at: nil) }
end
