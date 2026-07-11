# frozen_string_literal: true

class MeetingRequest < ApplicationRecord
  belongs_to :company
  belongs_to :report, optional: true
  belongs_to :reviewer_user
  belongs_to :reviewer_outreach, optional: true
  belongs_to :approved_by_company_user, class_name: "CompanyUser", optional: true

  STATUSES = %w[pending_admin approved declined scheduled completed cancelled].freeze
  validates :purpose, presence: true
  validates :status, inclusion: { in: STATUSES }

  def pending_admin?
    status == "pending_admin"
  end

  def append_audit!(action, actor:, note: nil)
    entry = {
      "at" => Time.current.iso8601,
      "action" => action.to_s,
      "actor_type" => actor.class.name,
      "actor_id" => actor.id,
      "note" => note
    }.compact
    update!(audit_trail: Array(audit_trail) + [entry])
  end
end
