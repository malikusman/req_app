# frozen_string_literal: true

class Company < ApplicationRecord
  has_one :subscription, dependent: :destroy
  has_many :company_users, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :conversation_insights, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :document_analysis_runs, dependent: :destroy
  has_many :company_knowledge_entries, dependent: :destroy
  has_many :company_clarification_questions, dependent: :destroy
  has_many :media_attachments, dependent: :destroy
  has_many :company_signals, dependent: :destroy
  has_many :patterns, dependent: :destroy
  has_many :recommendations, dependent: :destroy
  has_many :company_systems, dependent: :destroy
  has_many :agentic_ideas, dependent: :destroy
  has_many :insight_timeline_events, dependent: :destroy
  has_many :discovery_question_feedbacks, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :reviewer_assignments, dependent: :destroy
  has_many :reviewer_users, through: :reviewer_assignments
  has_many :reviewer_chat_messages, dependent: :destroy
  has_many :company_memory_facts, dependent: :destroy
  has_one :company_registration, dependent: :destroy

  def bot_phone_display
    ENV.fetch("META_WHATSAPP_DISPLAY_NUMBER", "+1 000 000 0000")
  end

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :website_url, format: { with: %r{\Ahttps?://}i, allow_blank: true }

  APPROVAL_STATUSES = %w[pending_approval approved rejected].freeze

  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }

  before_validation :generate_slug, on: :create

  scope :approved, -> { where(approval_status: "approved") }

  def approved_for_access?
    approval_status == "approved"
  end

  DEFAULT_SETTINGS = {
    "engagement_mode" => "hybrid",
    "discovery_question_target" => 10,
    "discovery_addendum_budget" => 3,
    "discovery_session_timeout_hours" => 72,
    "discovery_profiling_enabled" => true,
    "discovery_multi_agent_enabled" => true,
    "discovery_memory_retrieval_enabled" => true,
    "discovery_media_indexing_enabled" => true,
    "discovery_multimodal_enabled" => true,
    "discovery_max_followup_depth" => 2,
    "discovery_max_questions_per_agent" => 5,
    "discovery_max_active_agents" => 4,
    # Phase 3 — map-then-branch interview (orient -> per-area rotation). Off by
    # default; enable per company (or via AREA_ROUTING=1 in the simulator).
    "discovery_area_routing_enabled" => false,
    "discovery_orient_questions" => 3,
    "discovery_switch_after" => 2,
    "report_thresholds" => {
      "min_employees_interviewed" => 3,
      "min_departments" => 2,
      "min_patterns" => 1,
      "min_multimodal_contributions" => 1,
      "min_ready_documents" => 3,
      "min_document_departments" => 1
    },
    "department_targets" => {},
    "custom_departments" => []
  }.freeze

  ENGAGEMENT_MODES = %w[hybrid documents interview].freeze

  SIZE_BANDS = %w[1-10 11-50 51-200 201-500 500+].freeze

  def merged_settings
    DEFAULT_SETTINGS.deep_merge(self[:settings] || {})
  end

  def profile_value(key)
    (self[:company_profile] || {})[key.to_s].presence
  end

  def engagement_mode
    mode = merged_settings["engagement_mode"].to_s
    ENGAGEMENT_MODES.include?(mode) ? mode : "hybrid"
  end

  def docs_first_phase?
    (report_readiness_breakdown || {})["employees_interviewed"].to_i.zero?
  end

  def promote_to_hybrid_engagement!
    return unless engagement_mode == "documents"

    update!(settings: (settings || {}).merge("engagement_mode" => "hybrid"))
  end

  def onboarding_complete?
    portal_onboarding_completed_at.present?
  end

  private

  def generate_slug
    base = name.to_s.parameterize.presence || "company"
    candidate = base
    suffix = 0
    while self.class.exists?(slug: candidate)
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end
    self.slug ||= candidate
  end
end
