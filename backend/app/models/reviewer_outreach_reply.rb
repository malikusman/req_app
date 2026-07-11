# frozen_string_literal: true

class ReviewerOutreachReply < ApplicationRecord
  belongs_to :reviewer_outreach
  belongs_to :message, optional: true
  belongs_to :company_user, optional: true

  CHANNELS = %w[whatsapp email portal].freeze

  validates :channel, inclusion: { in: CHANNELS }
  validates :body, presence: true
  validates :received_at, presence: true
end
