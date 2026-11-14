# frozen_string_literal: true

class ProcessClusterMembership < ApplicationRecord
  belongs_to :process_cluster_revision, inverse_of: :memberships
  belongs_to :task_source

  attr_readonly :process_cluster_revision_id, :task_source_id, :effort_observations

  validates :task_source_id, uniqueness: { scope: :process_cluster_revision_id }
  validate :source_belongs_to_cluster_company

  private

  def source_belongs_to_cluster_company
    cluster = process_cluster_revision&.process_cluster
    if cluster && task_source && cluster.company_id != task_source.company_id
      errors.add(:task_source, "must belong to the cluster company")
    end
  end
end
