# frozen_string_literal: true

class BillingEvent < ApplicationRecord
  belongs_to :company

  validates :event_type, presence: true
  validates :occurred_at, presence: true
end
