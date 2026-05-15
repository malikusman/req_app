# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
end
