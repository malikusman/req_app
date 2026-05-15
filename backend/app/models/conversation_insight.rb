# frozen_string_literal: true

class ConversationInsight < ApplicationRecord
  belongs_to :conversation
  belongs_to :employee
  belongs_to :company
  belongs_to :message, optional: true

  validates :turn_number, :insight_type, presence: true
end
