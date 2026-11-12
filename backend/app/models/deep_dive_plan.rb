# frozen_string_literal: true

class DeepDivePlan < ApplicationRecord
  belongs_to :task_selection_revision
  has_many :revisions, class_name: "DeepDivePlanRevision", inverse_of: :deep_dive_plan

  attr_readonly :task_selection_revision_id, :task_key, :context
  validates :status, inclusion: { in: %w[queued generating failed draft approved] }
  validates :task_key, :generation_token, :context, presence: true
  validates :task_key, uniqueness: { scope: :task_selection_revision_id }
  validate :selected_task

  def latest_revision
    revisions.order(version: :desc).first
  end

  def approved_revision
    revisions.find_by(action: "approved") if status == "approved"
  end

  private

  def selected_task
    selection = task_selection_revision
    if selection&.status != "finalized" || !selection.snapshot.dig("final_selection", "tasks")&.any? { |task| task["id"] == task_key }
      errors.add(:task_key, "must belong to the finalized selection")
    end
  end
end
