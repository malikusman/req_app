# frozen_string_literal: true

# Work that several people describe, held as one process with its variants and
# stages preserved (Doc 10 §9, Doc 06 §6.1–6.2). Grouping never adds or removes
# hours by itself: each version has an EffortNormalization that says what the
# group costs once counted once.
#
# A cluster a consultant approved, split, merged or created is theirs: a re-run
# never changes its boundaries, only proposes additions (Doc 10 §21).
class SynthesisCluster < ApplicationRecord
  include SynthesisVersioned
  version_key :cluster_key

  SCHEMA_VERSION = "PC.v1"
  TYPES = %w[SHARED_IDENTICAL SHARED_VARIANT END_TO_END SEQUENTIAL_STAGE].freeze
  STATUSES = %w[PROVISIONAL APPROVED SUPERSEDED REJECTED].freeze
  ORIGINS = %w[AI CONSULTANT].freeze
  FACT_STATUSES = %w[INFERRED CONSULTANT_CONFIRMED].freeze
  CONFIDENCES = %w[HIGH MEDIUM LOW].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :synthesis_run, optional: true
  belongs_to :decided_by, polymorphic: true, optional: true
  has_many :members, class_name: "SynthesisClusterMember", dependent: :destroy
  has_many :findings, through: :members
  has_one :effort_normalization, dependent: :destroy

  validates :cluster_key, :name, presence: true
  validates :cluster_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :fact_status, inclusion: { in: FACT_STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCES }, allow_nil: true

  scope :approved, -> { where(status: "APPROVED") }

  # Boundaries a re-run must leave alone.
  def consultant_owned? = status == "APPROVED" || origin == "CONSULTANT" || decided_by_id.present?

  def finding_ids = members.map(&:finding_id)

  private

  # A new version keeps the same members and effort until the caller changes
  # them; the old version keeps its own.
  def copy_children(copy)
    members.each do |m|
      copy.members.create!(m.attributes.slice("finding_id", "employee_id", "variant_label", "stage_order",
                                              "member_digest"))
    end
    return unless effort_normalization

    copy.create_effort_normalization!(effort_normalization.attributes.except("id", "synthesis_cluster_id", "created_at",
                                                                             "updated_at"))
  end
end
