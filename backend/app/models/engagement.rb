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
  has_many :conversation_sessions, dependent: :destroy
  # Doc 17: Stage 1 is priced once the leadership conversation hands over.
  has_many :quotes, dependent: :destroy

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

  # Reaching pricing starts the Stage 1 quote (Doc 17 §1). After the commit, so
  # the job sees the hand-over however deep the transaction that made it.
  after_commit :propose_stage1_price, if: -> { saved_change_to_status? && status == "STAGE_1_PRICING" }

  def closed? = status == "CLOSED"

  # Mjadi may change who takes part until the client accepts the Stage 1 price;
  # in pricing, a change makes a fresh quote (Doc 17 §12). The client's own
  # scope card closes when pricing starts.
  def plan_open_to_mjadi? = %w[KEY_PERSON_DISCOVERY STAGE_1_PRICING].include?(status)

  # Departments and how many people from each will take part (P1, P2). The
  # total is nil while any department is still "Not sure", so nothing downstream
  # can mistake a partial count for the plan.
  def planned_participant_count
    counts = Array(planned_departments).map { |row| row["count"] }
    return nil if counts.empty? || counts.any? { |c| !c.is_a?(Integer) }

    counts.sum
  end

  # The Stage 1 quote with the administrator or the client, if there is one.
  def open_stage1_quote = quotes.stage1.open.order(version: :desc).first

  # The price the client agreed; fixed for the engagement (Decision Register B8).
  def accepted_stage1_quote = quotes.stage1.find_by(status: "ACCEPTED")

  def latest_stage1_quote = quotes.stage1.order(version: :desc).first

  def planned_count_for(department)
    row = Array(planned_departments).find { |r| r["name"].to_s.casecmp?(department.to_s) }
    row && row["count"].is_a?(Integer) ? row["count"] : nil
  end

  private

  def propose_stage1_price
    ProposeStage1Job.perform_later(id)
  end

  def departments_present_for_department_scope
    return unless scope_type == "DEPARTMENT" && Array(departments_in_scope).reject(&:blank?).empty?

    errors.add(:departments_in_scope, "must name at least one department for a department-scoped engagement")
  end
end
