# frozen_string_literal: true

# What Mjadi has agreed to do for a client, and where it has got to (Doc 06 §3.4).
# Status changes only through Engagements::Transition, which records each one in
# status_history.
class Engagement < ApplicationRecord
  belongs_to :company
  belongs_to :key_user, class_name: "CompanyUser", optional: true
  belongs_to :lead_consultant, class_name: "ConsultantUser", optional: true
  belongs_to :confidentiality_acknowledged_by, class_name: "CompanyUser", optional: true
  has_many :participants, class_name: "EngagementParticipant", dependent: :destroy
  has_many :prefill_candidates, dependent: :destroy

  # Doc 06 §3.5, Stage 1 so far. The later stages are added with the work that
  # moves an engagement into them. STAGE_1_PRICING is where the conversations with
  # leadership hand over to pricing (Doc 17 §1).
  STATUSES = %w[SET_UP ONBOARDING KEY_PERSON_DISCOVERY STAGE_1_PRICING STAGE_1_ACTIVE CLOSED].freeze
  SCOPE_TYPES = %w[COMPANY DEPARTMENT].freeze
  # Reading the website for pre-fill (Doc 07 §5): empty means nothing usable was
  # found or it couldn't be read, and the form is shown plain, without comment.
  PREFILL_STATUSES = %w[not_started pending running done empty failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :scope_type, inclusion: { in: SCOPE_TYPES }
  validates :prefill_status, inclusion: { in: PREFILL_STATUSES }
  validate :departments_present_for_department_scope

  scope :not_closed, -> { where.not(status: "CLOSED") }

  def closed? = status == "CLOSED"

  # Departments and how many people from each will take part (P1, P2). The
  # total is nil while any department is still "Not sure", so nothing downstream
  # can mistake a partial count for the plan.
  def planned_participant_count
    counts = Array(planned_departments).map { |row| row["count"] }
    return nil if counts.empty? || counts.any? { |c| !c.is_a?(Integer) }

    counts.sum
  end

  def planned_count_for(department)
    row = Array(planned_departments).find { |r| r["name"].to_s.casecmp?(department.to_s) }
    row && row["count"].is_a?(Integer) ? row["count"] : nil
  end

  private

  def departments_present_for_department_scope
    return unless scope_type == "DEPARTMENT" && Array(departments_in_scope).reject(&:blank?).empty?

    errors.add(:departments_in_scope, "must name at least one department for a department-scoped engagement")
  end
end
