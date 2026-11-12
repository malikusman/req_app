# frozen_string_literal: true

class TaskSelectionReview < ApplicationRecord
  belongs_to :company
  belongs_to :task_intelligence_run
  has_many :revisions, class_name: "TaskSelectionRevision", inverse_of: :task_selection_review

  attr_readonly :company_id, :task_intelligence_run_id
  validates :task_intelligence_run_id, uniqueness: true
  validate :run_belongs_to_company

  private

  def run_belongs_to_company
    errors.add(:task_intelligence_run, "must belong to the review company") if task_intelligence_run&.company_id != company_id
  end
end
