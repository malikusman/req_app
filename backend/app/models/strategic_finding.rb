# frozen_string_literal: true

# An issue or opportunity a key person raised (Doc 06 §5.2, Doc 08 §15). A
# reported management observation until later discovery supports it, with what
# that discovery should check. Management importance is theirs, not the
# platform's priority (§17).
#
# A consultant's edit makes a new version and supersedes the old one; a
# rejected finding is kept, marked rejected (Doc 06 §1.2).
class StrategicFinding < ApplicationRecord
  CATEGORIES = %w[PROCESS MANAGEMENT REPORTING SYSTEM INTEGRATION DATA TRAINING CHANGE GOVERNANCE AI AUTOMATION
                  ORGANISATION GROWTH RISK OTHER].freeze
  SCOPES = %w[COMPANY DEPARTMENT CROSS_DEPARTMENT].freeze
  SYMPTOM_OR_CAUSE = %w[SYMPTOM SUSPECTED_CAUSE].freeze
  SOURCE_BASES = %w[MANAGEMENT_STATEMENT ONBOARDING DOCUMENT INFERENCE].freeze
  FACT_STATUSES = %w[REPORTED INFERRED].freeze
  IMPORTANCE = %w[HIGH MEDIUM LOW].freeze
  STATUSES = %w[ACTIVE SUPERSEDED REJECTED].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :management_discovery_context
  belongs_to :parent_version, class_name: "StrategicFinding", optional: true
  belongs_to :edited_by, polymorphic: true, optional: true

  validates :category, inclusion: { in: CATEGORIES }
  validates :scope, inclusion: { in: SCOPES }
  validates :source_basis, inclusion: { in: SOURCE_BASES }
  validates :fact_status, inclusion: { in: FACT_STATUSES }
  validates :status, inclusion: { in: STATUSES }
  validates :statement, presence: true
  validates :evidence, presence: true

  scope :active, -> { where(status: "ACTIVE") }
end
