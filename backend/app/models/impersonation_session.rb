# frozen_string_literal: true

class ImpersonationSession < ApplicationRecord
  belongs_to :platform_user
  belongs_to :company_user
  belongs_to :company

  scope :active, -> { where(ended_at: nil).where("expires_at > ?", Time.current) }

  def end!
    update!(ended_at: Time.current)
  end
end
