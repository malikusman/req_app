# frozen_string_literal: true

# A consultant's decision on synthesis, with why (Doc 10 §17.2, Doc 05 §9.3).
# Append-only: what was decided, on which version, what it produced and what
# had to be recomputed as a result.
class SynthesisDecision < ApplicationRecord
  ACTIONS = %w[APPROVE_CLUSTER SPLIT_CLUSTER MERGE_CLUSTERS CHANGE_VARIANT OVERRIDE_EFFORT REJECT_CLUSTER
               APPROVE_OPPORTUNITY RECLASSIFY_OPPORTUNITY ADD_OPPORTUNITY DEFER REJECT_OPPORTUNITY
               APPROVE_ROOT_CAUSE REJECT_ROOT_CAUSE
               APPROVE_VALIDATION RESOLVE_VALIDATION REQUEST_CLARIFICATION
               EDIT_OPERATING_PICTURE APPROVE_OPERATING_PICTURE
               CLASSIFY_PAIR].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :subject, polymorphic: true
  belongs_to :actor, polymorphic: true

  validates :action, inclusion: { in: ACTIONS }
  validates :rationale, presence: true

  def readonly? = persisted?
end
