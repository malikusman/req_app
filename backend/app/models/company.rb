# frozen_string_literal: true

class Company < ApplicationRecord
  has_one :subscription, dependent: :destroy
  has_many :company_users, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :conversation_insights, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :media_attachments, dependent: :destroy
  has_many :company_signals, dependent: :destroy
  has_many :patterns, dependent: :destroy
  has_many :recommendations, dependent: :destroy
  has_many :insight_timeline_events, dependent: :destroy
  has_many :discovery_question_feedbacks, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :reviewer_assignments, dependent: :destroy
  has_many :reviewer_users, through: :reviewer_assignments
  has_many :reviewer_chat_messages, dependent: :destroy
  has_many :company_memory_facts, dependent: :destroy

  def bot_phone_display
    ENV.fetch("META_WHATSAPP_DISPLAY_NUMBER", "+1 000 000 0000")
  end

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }

  before_validation :generate_slug, on: :create

  DEFAULT_SETTINGS = {
    "engagement_mode" => "hybrid",
    "discovery_question_target" => 10,
    "discovery_session_timeout_hours" => 72,
    "discovery_profiling_enabled" => true,
    "discovery_multi_agent_enabled" => true,
    "discovery_memory_retrieval_enabled" => true,
    "discovery_media_indexing_enabled" => true,
    "discovery_multimodal_enabled" => true,
    "discovery_max_followup_depth" => 2,
    "discovery_max_questions_per_agent" => 5,
    "discovery_max_active_agents" => 4,
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

  def merged_settings
    DEFAULT_SETTINGS.deep_merge(self[:settings] || {})
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
    self.slug ||= name.to_s.parameterize
  end
end
