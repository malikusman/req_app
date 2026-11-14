# frozen_string_literal: true

# An opportunity above the individual task — shared, process, department,
# cross-department or company-wide (Doc 10 §12, Doc 06 §6.5) — with a direction,
# never a design, and what should happen next.
#
# Management importance and platform priority are stored apart and never
# merged (Doc 10 §15, Doc 08 §17): the first is what leadership said mattered,
# the second is Synthesis::Priority's reading of the evidence.
class ConsultancyOpportunity < ApplicationRecord
  include SynthesisVersioned
  version_key :opportunity_key

  SCHEMA_VERSION = "CO.v1"
  # Doc 10 §12.3–12.5 / P11. Doc 06 §6.5 uses coarser names; the maps below
  # translate ours for anything that reads the object contract's.
  LEVELS = %w[INDIVIDUAL_TASK SHARED_TASK PROCESS DEPARTMENT CROSS_DEPARTMENT COMPANY_WIDE].freeze
  DOC06_LEVELS = {
    "INDIVIDUAL_TASK" => "INDIVIDUAL", "SHARED_TASK" => "SHARED", "PROCESS" => "PROCESS",
    "DEPARTMENT" => "DEPARTMENT", "CROSS_DEPARTMENT" => "CROSS_DEPARTMENT", "COMPANY_WIDE" => "COMPANY"
  }.freeze
  CATEGORIES = %w[PROCESS MANAGEMENT REPORTING SYSTEMS INTEGRATION DATA TRAINING CHANGE GOVERNANCE AI AUTOMATION
                  RISK HYBRID].freeze
  DOC06_CATEGORIES = {
    "SYSTEMS" => "SYSTEM", "CHANGE" => "ORGANISATION", "AUTOMATION" => "AI", "RISK" => "GOVERNANCE",
    "HYBRID" => "PROCESS"
  }.freeze
  NEXT_ACTIONS = %w[DEEP_DIVE DIRECT_FINDING CLARIFY TECHNOLOGY_REVIEW DEFER NOT_RECOMMENDED].freeze
  DOC06_NEXT_ACTIONS = {
    "DEEP_DIVE" => "DEEP_DIVE", "DIRECT_FINDING" => "DIRECT_FINDING", "CLARIFY" => "CLARIFY",
    "TECHNOLOGY_REVIEW" => "CLARIFY", "DEFER" => "NONE", "NOT_RECOMMENDED" => "NONE"
  }.freeze
  OTHER_VALUES = %w[SERVICE QUALITY REVENUE RISK VISIBILITY SCALABILITY].freeze
  AI_RELEVANCE = %w[PRIMARY SUPPORTING NONE].freeze
  STATUSES = %w[PROPOSED APPROVED DEFERRED REJECTED SUPERSEDED].freeze
  PRIORITIES = %w[HIGH MEDIUM LOW].freeze
  CONFIDENCES = %w[HIGH MEDIUM LOW].freeze
  ORIGINS = %w[AI CONSULTANT].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :synthesis_run, optional: true

  validates :opportunity_key, :title, :problem_statement, presence: true
  validates :level, inclusion: { in: LEVELS }
  validates :category, inclusion: { in: CATEGORIES }
  validates :recommended_next_action, inclusion: { in: NEXT_ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :ai_relevance, inclusion: { in: AI_RELEVANCE }, allow_nil: true
  validates :management_importance, :platform_priority, inclusion: { in: PRIORITIES }, allow_nil: true
  validate :other_values_known

  scope :approved, -> { where(status: "APPROVED") }

  private

  def other_values_known
    unknown = Array(other_value) - OTHER_VALUES
    errors.add(:other_value, "unknown: #{unknown.join(', ')}") if unknown.any?
  end
end
