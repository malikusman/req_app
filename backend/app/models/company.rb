# frozen_string_literal: true

class Company < ApplicationRecord
  include CompanyJoinCode

  LOCALES = %w[en es ar].freeze

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
  has_many :billing_events, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :reviewer_assignments, dependent: :destroy
  has_many :reviewer_users, through: :reviewer_assignments
  has_many :reviewer_chat_messages, dependent: :destroy
  has_many :company_info_requests, dependent: :destroy
  has_many :knowledge_chunks, dependent: :destroy
  has_many :agent_interrupts, dependent: :destroy

  def bot_phone_display
    ENV.fetch("META_WHATSAPP_DISPLAY_NUMBER", "+1 000 000 0000")
  end

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :locale, inclusion: { in: LOCALES }

  before_validation :generate_slug, on: :create

  DEFAULT_SETTINGS = {
    "discovery_question_target" => 10,
    "discovery_session_timeout_hours" => 72,
    "report_thresholds" => {
      "min_employees_interviewed" => 3,
      "min_departments" => 2,
      "min_patterns" => 1,
      "min_multimodal_contributions" => 1
    },
    "department_targets" => {},
    "custom_departments" => []
  }.freeze

  def merged_settings
    DEFAULT_SETTINGS.merge(self[:settings] || {})
  end

  def onboarding_complete?
    portal_onboarding_completed_at.present?
  end

  def profile_completeness
    Companies::ProfileCompleteness.new(company: self)
  end

  def merge_profile_section!(section:, data:)
    sanitized = Companies::ProfileContextSchema.sanitize_section_data(section, data)
    merged = (profile_context || {}).deep_merge(section.to_s => sanitized)
    update!(profile_context: merged)
    Knowledge::IndexProfileJob.perform_later(id)
  end

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end
