# frozen_string_literal: true

# One version of an activity observed in one Discovery conversation.
class TaskSource < ApplicationRecord
  SOURCE_KINDS = %w[workflow_ledger legacy_slots].freeze

  belongs_to :company
  belongs_to :employee
  belongs_to :conversation
  belongs_to :finding, optional: true

  attr_readonly :company_id, :employee_id, :conversation_id, :source_kind, :local_task_id,
                :name, :description, :discovery_revision, :version, :source_snapshot, :evidence_references,
                :finding_id, :retired

  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :local_task_id, presence: true, length: { maximum: 255 }
  validates :name, :source_snapshot, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 },
                      uniqueness: { scope: %i[conversation_id source_kind local_task_id] }
  validates :discovery_revision, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :source_associations_agree

  def self.evidence_messages
    Message.where(direction: "inbound", track: %w[discovery profiling]).where.not(message_type: "system")
  end

  private

  def source_associations_agree
    if conversation && (conversation.company_id != company_id || conversation.employee_id != employee_id)
      errors.add(:conversation, "must belong to the source company and employee")
    end
    if employee && employee.company_id != company_id
      errors.add(:employee, "must belong to the source company")
    end
    if finding && (finding.company_id != company_id || finding.employee_id != employee_id ||
                   finding.conversation_id != conversation_id)
      errors.add(:finding, "must belong to the source company, employee and conversation")
    end
  end
end
