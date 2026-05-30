# frozen_string_literal: true

class KnowledgeChunk < ApplicationRecord
  belongs_to :company

  SOURCE_TYPES = %w[conversation_insight profile_section].freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :content, presence: true

  has_neighbors :embedding
end
