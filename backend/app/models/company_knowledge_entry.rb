# frozen_string_literal: true

class CompanyKnowledgeEntry < ApplicationRecord
  belongs_to :company
  belongs_to :document_analysis_run, optional: true

  ENTRY_TYPES = %w[process policy system org metric risk other].freeze
  STATUSES = %w[active superseded orphaned].freeze

  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :title, :content, presence: true

  scope :active, -> { where(status: "active") }
  has_neighbors :embedding
end
