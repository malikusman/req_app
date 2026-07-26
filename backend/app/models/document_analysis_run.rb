# frozen_string_literal: true

class DocumentAnalysisRun < ApplicationRecord
  belongs_to :company
  belongs_to :triggered_by_company_user, class_name: "CompanyUser", optional: true
  has_many :document_analysis_events, dependent: :destroy
  has_many :company_knowledge_entries, dependent: :nullify
  has_many :company_clarification_questions, dependent: :nullify

  RUN_KINDS = %w[full incremental_docs profile_reground].freeze
  STATUSES = %w[queued running completed completed_with_errors failed].freeze

  validates :run_kind, inclusion: { in: RUN_KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[queued running]) }
  scope :recent, -> { order(created_at: :desc) }

  def active?
    status.in?(%w[queued running])
  end
end
