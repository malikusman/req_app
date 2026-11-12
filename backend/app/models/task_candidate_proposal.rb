# frozen_string_literal: true

class TaskCandidateProposal < ApplicationRecord
  DISPOSITIONS = %w[shortlisted needs_overlap_review insufficient_evidence deferred_capacity].freeze

  belongs_to :task_intelligence_run, inverse_of: :candidates
  belongs_to :process_cluster_revision

  attr_readonly :task_intelligence_run_id, :process_cluster_revision_id, :title, :disposition,
                :disposition_reason, :rank, :score, :priority, :confidence, :assessment

  validates :title, :disposition_reason, :assessment, presence: true
  validates :disposition, inclusion: { in: DISPOSITIONS }
  validates :priority, :confidence, inclusion: { in: %w[high medium low] }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :rank, numericality: { only_integer: true, greater_than: 0 },
                   uniqueness: { scope: :task_intelligence_run_id }, if: :shortlisted?
  validates :rank, absence: true, unless: :shortlisted?
  validates :process_cluster_revision_id, uniqueness: { scope: :task_intelligence_run_id }
  validate :cluster_belongs_to_run_company

  def shortlisted?
    disposition == "shortlisted"
  end

  private

  def cluster_belongs_to_run_company
    cluster = process_cluster_revision&.process_cluster
    if cluster && task_intelligence_run && cluster.company_id != task_intelligence_run.company_id
      errors.add(:process_cluster_revision, "must belong to the run company")
    end
  end
end
