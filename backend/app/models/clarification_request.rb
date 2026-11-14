# frozen_string_literal: true

# An internal consolidation evidence gap. CompanyClarificationQuestion remains
# the separate, client-facing document analysis workflow.
class ClarificationRequest < ApplicationRecord
  belongs_to :company
  belongs_to :left_source, class_name: "TaskSource"
  belongs_to :right_source, class_name: "TaskSource"

  attr_readonly :company_id, :pair_key

  validates :pair_key, presence: true, uniqueness: { scope: :company_id }
  validates :status, inclusion: { in: %w[open resolved closed] }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :details, presence: true
  validate :validate_source_scope

  def snapshot
    { "id" => id, "version" => version, "status" => status, "details" => details }
  end

  private

  def validate_source_scope
    if [left_source, right_source].compact.any? { |source| source.company_id != company_id }
      errors.add(:base, "Both sources must belong to the request company")
    end
    if left_source && right_source && left_source.conversation_id == right_source.conversation_id
      errors.add(:right_source, "must belong to a different conversation")
    end
  end
end
