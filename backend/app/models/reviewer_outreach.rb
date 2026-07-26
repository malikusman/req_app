# frozen_string_literal: true

class ReviewerOutreach < ApplicationRecord
  belongs_to :company
  belongs_to :report, optional: true
  belongs_to :reviewer_user
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :approved_by_company_user, class_name: "CompanyUser", optional: true
  belongs_to :message, optional: true
  belongs_to :reviewer_info_request, optional: true

  has_many :reviewer_outreach_replies, dependent: :destroy

  STATUSES = %w[
    draft pending_admin_approval approved declined queued sent replied closed failed
  ].freeze
  RECIPIENT_TYPES = %w[employee company_admin].freeze
  PURPOSES = %w[clarification evidence_request].freeze
  CHANNELS = %w[whatsapp email portal].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :recipient_type, inclusion: { in: RECIPIENT_TYPES }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :channel, inclusion: { in: CHANNELS }
  validates :body, presence: true

  scope :pending_admin, -> { where(status: "pending_admin_approval") }
  scope :approved, -> { where(status: "approved") }
  scope :sent, -> { where(status: "sent") }
  scope :awaiting_reply, -> { where(status: %w[sent replied]) }

  def self.open_whatsapp_for_employee(employee_id)
    awaiting_reply
      .where(employee_id: employee_id, channel: "whatsapp", recipient_type: "employee")
      .order(Arel.sql("sent_at DESC NULLS LAST"), created_at: :desc)
      .first
  end

  def pending_admin?
    status == "pending_admin_approval"
  end

  def approved?
    status == "approved" || approved_at.present?
  end

  def delivery_body
    edited_body.presence || body
  end

  def append_audit!(action, actor:, note: nil)
    entry = {
      "action" => action.to_s,
      "at" => Time.current.iso8601,
      "actor_type" => actor.class.name,
      "actor_id" => actor.id,
      "note" => note
    }.compact
    update!(audit_trail: Array(audit_trail) + [entry])
  end
end
