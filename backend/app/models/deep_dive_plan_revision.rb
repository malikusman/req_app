# frozen_string_literal: true

class DeepDivePlanRevision < ApplicationRecord
  belongs_to :deep_dive_plan, inverse_of: :revisions
  belongs_to :consultant_user

  attr_readonly :deep_dive_plan_id, :consultant_user_id, :version, :action, :reason, :content
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :deep_dive_plan_id }
  validates :action, inclusion: { in: %w[generated edited approved] }
  validates :reason, :content, presence: true
end
