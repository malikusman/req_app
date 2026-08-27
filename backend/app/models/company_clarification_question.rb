# frozen_string_literal: true

class CompanyClarificationQuestion < ApplicationRecord
  belongs_to :company
  belongs_to :document_analysis_run, optional: true
  belongs_to :answered_by_company_user, class_name: "CompanyUser", optional: true
  belongs_to :dismissed_by_consultant_user, class_name: "ConsultantUser", optional: true

  STATUSES = %w[pending_rag auto_answered open answered dismissed_by_consultant stale].freeze
  ANSWER_SOURCES = %w[rag admin].freeze

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :answer_source, inclusion: { in: ANSWER_SOURCES }, allow_nil: true

  scope :visible_to_admin, -> { where(status: %w[open auto_answered answered]) }
  scope :open_for_admin, -> { where(status: "open") }
  scope :for_consultant, -> { where.not(status: "pending_rag") }
end
