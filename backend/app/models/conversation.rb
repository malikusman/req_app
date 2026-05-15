# frozen_string_literal: true

class Conversation < ApplicationRecord
  belongs_to :employee
  belongs_to :company
  has_many :messages, dependent: :destroy
  has_many :conversation_insights, dependent: :destroy
  has_many :media_attachments, dependent: :destroy
  has_many :documents, dependent: :nullify
  has_many :employee_nudges, dependent: :nullify

  STATUSES = %w[onboarding discovery completed abandoned].freeze

  validates :status, inclusion: { in: STATUSES }

  def touch_activity!
    update!(last_activity_at: Time.current)
  end

  def discovery?
    status == "discovery"
  end
end
