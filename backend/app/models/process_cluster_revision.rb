# frozen_string_literal: true

class ProcessClusterRevision < ApplicationRecord
  belongs_to :process_cluster, inverse_of: :revisions
  has_many :memberships, class_name: "ProcessClusterMembership", inverse_of: :process_cluster_revision

  attr_readonly :process_cluster_id, :number, :status, :confidence, :rationale,
                :fingerprint, :relationships, :effort_summary

  validates :number, numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :process_cluster_id }
  validates :status, inclusion: { in: %w[active retired] }
  validates :confidence, inclusion: { in: %w[high medium low] }
  validates :rationale, :fingerprint, presence: true
end
