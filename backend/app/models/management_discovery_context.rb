# frozen_string_literal: true

# One key person's view of the business, from one conversation (Doc 06 §5.1,
# Doc 08 §16). Built by P04 when the conversation finishes; a later session
# adds a new version linked to this one.
#
# Never shown to the client or to employees. The neutral context is the only
# part meant to travel, and only through Companies::AgentContext.
class ManagementDiscoveryContext < ApplicationRecord
  SCHEMA_VERSION = "MDC.v1"
  # COMPLETE: built by P04 and validated. INCOMPLETE: P04 couldn't be used, so
  # it was built from the turn captures alone and flagged for the consultant.
  STATUSES = %w[COMPLETE INCOMPLETE].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :participant, class_name: "EngagementParticipant", foreign_key: :engagement_participant_id,
                           inverse_of: false
  belongs_to :session, class_name: "ConversationSession", foreign_key: :conversation_session_id, inverse_of: false
  belongs_to :parent_version, class_name: "ManagementDiscoveryContext", optional: true
  has_many :strategic_findings, dependent: :destroy
  has_many :planned_initiatives, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  # Each person's latest version, for one engagement.
  scope :latest_per_participant, lambda {
    where(id: select("DISTINCT ON (engagement_participant_id) id")
              .order(:engagement_participant_id, version: :desc))
  }
end
