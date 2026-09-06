# frozen_string_literal: true

# Company long-term memory: structured facts promoted from completed discovery
# conversations (and later consultant Q&A), embedded for cross-employee retrieval.
class CompanyMemoryFact < ApplicationRecord
  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true

  FACT_TYPES = %w[finding tool process_step pain_point consultant_learning].freeze

  has_neighbors :embedding

  validates :content, presence: true
  validates :fact_type, inclusion: { in: FACT_TYPES }

  scope :embedded, -> { where.not(embedding: nil) }
end
