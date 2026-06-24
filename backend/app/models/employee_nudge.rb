# frozen_string_literal: true

class EmployeeNudge < ApplicationRecord
  DELIVERY_STATUSES = %w[queued sent partial failed].freeze
  CHANNEL_STATUSES = %w[queued sent failed skipped].freeze

  belongs_to :employee
  belongs_to :company_user, optional: true
  belongs_to :conversation, optional: true

  validates :delivery_status, inclusion: { in: DELIVERY_STATUSES }

  def whatsapp_channel?
    channel.in?(%w[whatsapp_template whatsapp_and_email])
  end

  def email_channel?
    channel.in?(%w[email whatsapp_and_email])
  end
end
