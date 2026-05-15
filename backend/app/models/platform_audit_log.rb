# frozen_string_literal: true

class PlatformAuditLog < ApplicationRecord
  belongs_to :platform_user

  validates :action, presence: true
end
