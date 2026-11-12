# frozen_string_literal: true

# Synthesis keeps its own clusters (SynthesisCluster) for the report. This is
# the table meant to remain once the two engines keep one set (docs/CONSOLIDATION_ENGINES.md §3).
class ProcessCluster < ApplicationRecord
  belongs_to :company
  has_many :revisions, class_name: "ProcessClusterRevision", inverse_of: :process_cluster
  has_one :current_revision, -> { order(number: :desc) }, class_name: "ProcessClusterRevision"

  attr_readonly :company_id, :anchor_key

  validates :anchor_key, presence: true, uniqueness: { scope: :company_id }
end
