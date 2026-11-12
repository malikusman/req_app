# frozen_string_literal: true

class ProcessCluster < ApplicationRecord
  belongs_to :company
  has_many :revisions, class_name: "ProcessClusterRevision", inverse_of: :process_cluster
  has_one :current_revision, -> { order(number: :desc) }, class_name: "ProcessClusterRevision"

  attr_readonly :company_id, :anchor_key

  validates :anchor_key, presence: true, uniqueness: { scope: :company_id }
end
