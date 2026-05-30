# frozen_string_literal: true

class AgentCopilotMessage < ApplicationRecord
  belongs_to :company
  belongs_to :reviewer_user

  validates :thread_id, :role, :body, presence: true
end
