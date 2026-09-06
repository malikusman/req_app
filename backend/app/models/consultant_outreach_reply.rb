# frozen_string_literal: true

class ConsultantOutreachReply < ApplicationRecord
  belongs_to :consultant_outreach
  belongs_to :message, optional: true
  belongs_to :company_user, optional: true

  CHANNELS = %w[whatsapp email portal].freeze

  validates :channel, inclusion: { in: CHANNELS }
  validates :body, presence: true
  validates :received_at, presence: true
end
