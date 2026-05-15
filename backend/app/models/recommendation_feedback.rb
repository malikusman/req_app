# frozen_string_literal: true

class RecommendationFeedback < ApplicationRecord
  belongs_to :recommendation
  belongs_to :company_user

  validates :feedback, presence: true
end
