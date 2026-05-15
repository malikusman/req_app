# frozen_string_literal: true

class DiscoveryQuestionFeedback < ApplicationRecord
  belongs_to :company
  belongs_to :message
  belongs_to :company_user

  FEEDBACKS = %w[relevant not_relevant off_track].freeze

  validates :feedback, inclusion: { in: FEEDBACKS }
end
