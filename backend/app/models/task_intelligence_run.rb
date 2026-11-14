# frozen_string_literal: true

class TaskIntelligenceRun < ApplicationRecord
  belongs_to :company
  has_many :candidates, class_name: "TaskCandidateProposal", inverse_of: :task_intelligence_run

  attr_readonly :company_id, :version, :target_size, :algorithm_version, :evaluation_mode, :fingerprint

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :company_id }
  validates :target_size, numericality: { only_integer: true, greater_than: 0 }
  validates :algorithm_version, :evaluation_mode, :fingerprint, presence: true
end
