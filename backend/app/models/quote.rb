# frozen_string_literal: true

# A price put to a client (Doc 06 §10.10 QuoteRecord, Doc 17 §10). Stage 1 is
# the only stage priced so far; the stages after it use the same record.
#
#   PROPOSED   calculated, with the administrator
#   ISSUED     approved by an administrator and sent to the client (Doc 17 §9.2:
#              approving issues it, so approval is recorded on the issued quote)
#   ACCEPTED   the client's key user accepted it (§10.3)
#   DECLINED   the key user declined it
#   EXPIRED    its validity date passed before it was accepted
#   REJECTED   the administrator sent it back, with a note
#   SUPERSEDED a later version replaced it — an adjustment, new inputs, or a
#              change to the plan
#
# Never overwritten: the figures are fixed when it is made, and anything that
# changes them is a new version (Doc 06 §1.2). What is internal — the estimate,
# hours, cost and margin — is INTERNAL_COMMERCIAL and never leaves through a
# client view (Pricing::ClientQuoteView; Doc 05 §4.2, Doc 17 §15).
class Quote < ApplicationRecord
  STAGES = %w[STAGE_1 STAGE_2 STAGE_3_INDICATIVE STAGE_3_FIRM].freeze
  STATUSES = %w[PROPOSED ISSUED ACCEPTED DECLINED EXPIRED REJECTED SUPERSEDED].freeze
  OPEN_STATUSES = %w[PROPOSED ISSUED].freeze
  EXPLANATION_SOURCES = %w[P24 TEMPLATE].freeze

  # Fixed at creation (valid_until once, when it is issued).
  FIXED = %w[engagement_id company_id quote_stage version parent_quote_id currency rate_card_version_id
             margin_floor_version_id inputs estimate line_items subtotal tax_rate tax_amount total
             additional_participant_rate participants_included deep_dives_included internal margin_percent
             below_floor].freeze

  belongs_to :engagement
  belongs_to :company
  belongs_to :rate_card_version
  belongs_to :margin_floor_version
  belongs_to :parent_quote, class_name: "Quote", optional: true
  belongs_to :approved_by, class_name: "PlatformUser", optional: true
  belongs_to :rejected_by, class_name: "PlatformUser", optional: true
  belongs_to :accepted_by, class_name: "CompanyUser", optional: true
  belongs_to :declined_by, class_name: "CompanyUser", optional: true
  has_many :estimate_overrides, dependent: :delete_all
  has_many :events, -> { order(:created_at, :id) }, class_name: "QuoteEvent", dependent: :delete_all

  validates :quote_stage, inclusion: { in: STAGES }
  validates :status, inclusion: { in: STATUSES }
  validates :explanation_source, inclusion: { in: EXPLANATION_SOURCES }
  validates :version, presence: true, uniqueness: { scope: %i[engagement_id quote_stage] }
  validates :currency, :subtotal, :total, :additional_participant_rate, :margin_percent, presence: true
  validates :participants_included, :deep_dives_included, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :figures_fixed, on: :update
  validate :approved_before_issue
  validate :accepted_by_someone

  scope :stage1, -> { where(quote_stage: "STAGE_1") }
  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :proposed, -> { where(status: "PROPOSED") }

  def proposed? = status == "PROPOSED"
  def issued? = status == "ISSUED"
  def accepted? = status == "ACCEPTED"
  def open? = OPEN_STATUSES.include?(status)

  def past_validity?(today = Time.zone.today) = valid_until.present? && today > valid_until

  def self.next_version_for(engagement, stage)
    (where(engagement: engagement, quote_stage: stage).maximum(:version) || 0) + 1
  end

  def record!(event, actor: nil, detail: {})
    events.create!(event: event, actor: actor, detail: detail)
  end

  private

  def figures_fixed
    touched = FIXED & changed
    touched << "valid_until" if valid_until_changed? && valid_until_was.present?
    errors.add(:base, "A quote's figures can't change; make a new version (#{touched.join(', ')})") if touched.any?
  end

  def approved_before_issue
    return unless %w[ISSUED ACCEPTED DECLINED EXPIRED].include?(status)
    return if approved_by_id.present? && approved_at.present? && valid_until.present?

    errors.add(:base, "An administrator must approve a quote before it reaches the client")
  end

  def accepted_by_someone
    return unless accepted?
    return if accepted_by_id.present? && accepted_at.present?

    errors.add(:base, "An accepted quote records who accepted it and when")
  end
end
