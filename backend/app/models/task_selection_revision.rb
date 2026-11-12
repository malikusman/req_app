# frozen_string_literal: true

class TaskSelectionRevision < ApplicationRecord
  belongs_to :task_selection_review, inverse_of: :revisions
  belongs_to :consultant_user

  attr_readonly :task_selection_review_id, :consultant_user_id, :version, :action, :reason, :status, :snapshot
  validates :version, numericality: { only_integer: true, greater_than: 0 },
                      uniqueness: { scope: :task_selection_review_id }
  validates :action, :reason, :snapshot, presence: true
  validates :status, inclusion: { in: %w[draft finalized] }
end
