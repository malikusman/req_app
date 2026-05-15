# frozen_string_literal: true

class DocumentChunk < ApplicationRecord
  belongs_to :document

  has_neighbors :embedding

  validates :chunk_index, :content, presence: true
end
