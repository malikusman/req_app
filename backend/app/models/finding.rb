# frozen_string_literal: true

# One piece of work, in one role, that costs the company something. See the
# create_findings migration for why this exists alongside company signals.
class Finding < ApplicationRecord
  STATUSES = %w[draft approved hidden merged].freeze
  BASES = %w[discovery discovery_partial deep_dive consultant].freeze
  CONFIDENCES = %w[high medium low].freeze
  FREQUENCY_UNITS = %w[per_day per_week per_month per_quarter per_year per_event].freeze
  DURATION_UNITS = %w[minutes hours days].freeze
  EFFORT_TYPES = %w[active waiting mixed unknown].freeze

  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :merged_into, class_name: "Finding", optional: true
  has_many :merged_findings, class_name: "Finding", foreign_key: :merged_into_id, dependent: :nullify

  validates :source_key, :area, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :basis, inclusion: { in: BASES }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :effort_type, inclusion: { in: EFFORT_TYPES }
  validates :frequency_unit, inclusion: { in: FREQUENCY_UNITS }, allow_nil: true
  validates :duration_unit, inclusion: { in: DURATION_UNITS }, allow_nil: true

  belongs_to :reviewed_by, class_name: "ConsultantUser", optional: true

  scope :live, -> { where.not(status: %w[hidden merged]) }

  validate :merge_target_is_a_live_sibling

  def hours?
    annual_hours_min.present? && annual_hours_max.present?
  end

  # What a client would read: the consultant's wording where they gave one, the
  # interview's otherwise. The machine text itself is never changed.
  def display_title = consultant_title.presence || title.presence || area
  def display_what_happens_now = consultant_what_happens_now.presence || what_happens_now
  def display_friction = consultant_friction.presence || friction

  # A finding about the only person in a role identifies them, so it may not reach a
  # client until a consultant has looked at it.
  def needs_review? = single_occupant_role && status == "draft"

  private

  def merge_target_is_a_live_sibling
    return if merged_into_id.blank?

    target = merged_into
    if target.nil? || target.company_id != company_id
      errors.add(:merged_into, "must be a finding for the same company")
    elsif target.id == id
      errors.add(:merged_into, "cannot be the finding itself")
    elsif target.status == "merged"
      errors.add(:merged_into, "is itself merged into another finding")
    end
  end
end
