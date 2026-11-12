# frozen_string_literal: true

# How two pieces of work described by different people relate (Doc 10 §8,
# Doc 06 §6.3), as P10 judged it or as the platform fell back to. A fallback is
# always INDEPENDENT: under-merging shows as two similar findings a consultant
# can group; over-merging hides work nobody notices is missing (P10 §8).
#
# The deep-dive engine keeps the same judgement in its own shape, on each
# ProcessClusterRevision's relationships; one of the two goes when the engines
# are joined, and a CLARIFY pair becomes a ClarificationRequest
# (docs/CONSOLIDATION_ENGINES.md §3, §5).
class ProcessRelationship < ApplicationRecord
  include SynthesisVersioned
  version_key :pair_digest

  SCHEMA_VERSION = "PR.v1"
  # Doc 10 §8.1 / P10. Doc 06 §6.3 names fewer, coarser edges; DOC06_TYPES maps
  # ours onto them for anything that reads the object contract's names.
  TYPES = %w[SAME_PROCESS DUPLICATE_WORK PROCESS_STAGE SHARED_SUBPROCESS VARIANT ROOT_CAUSE_LINKED
             DEPENDENCY OBSOLETED_BY_INITIATIVE INDEPENDENT].freeze
  DOC06_TYPES = {
    "SAME_PROCESS" => "DUPLICATE_OF", "DUPLICATE_WORK" => "DUPLICATE_OF", "PROCESS_STAGE" => "STAGE_OF",
    "SHARED_SUBPROCESS" => "STAGE_OF", "VARIANT" => "VARIANT_OF", "ROOT_CAUSE_LINKED" => "SHARES_ROOT_CAUSE",
    "DEPENDENCY" => "BLOCKS", "OBSOLETED_BY_INITIATIVE" => "OBSOLETED_BY_INITIATIVE", "INDEPENDENT" => nil
  }.freeze
  CONFIDENCES = %w[HIGH MEDIUM LOW].freeze
  RECOMMENDATIONS = %w[AUTO_CLUSTER PROVISIONAL_CLUSTER KEEP_SEPARATE CONSULTANT_REVIEW CLARIFY].freeze
  # Only these recommendations put two items in one cluster; never at LOW.
  CLUSTERING = %w[AUTO_CLUSTER PROVISIONAL_CLUSTER].freeze
  SAME_EXECUTION = %w[YES NO UNKNOWN].freeze
  # FALLBACK: the model could not be used, so the pair was kept separate and
  # queued for the consultant. CONSULTANT: set by a consultant's decision.
  ORIGINS = %w[AI FALLBACK CONSULTANT].freeze
  STATUSES = %w[CURRENT SUPERSEDED].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :synthesis_run, optional: true
  belongs_to :from_finding, class_name: "Finding"
  belongs_to :to_finding, class_name: "Finding"

  validates :relationship_type, inclusion: { in: TYPES }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :recommendation, inclusion: { in: RECOMMENDATIONS }
  validates :same_execution, inclusion: { in: SAME_EXECUTION }
  validates :origin, inclusion: { in: ORIGINS }
  validates :status, inclusion: { in: STATUSES }
  validates :pair_digest, presence: true
  validate :never_clusters_at_low_confidence

  # Whether this edge joins its two items into one cluster.
  def clusters? = CLUSTERING.include?(recommendation) && confidence != "LOW"

  # Waiting on the consultant: the model could not settle it, or could not be used.
  def needs_review? = origin == "FALLBACK" || %w[CONSULTANT_REVIEW CLARIFY].include?(recommendation)

  private

  def never_clusters_at_low_confidence
    errors.add(:recommendation, "cannot cluster at LOW confidence") if CLUSTERING.include?(recommendation) &&
                                                                       confidence == "LOW"
  end
end
