# frozen_string_literal: true

# One sitting of a conversation with a participant (Doc 06 §4.1). So far only the
# conversations with leadership (Doc 08) use it; the employee interview keeps its
# own Conversation and Message records.
#
# The platform owns the conversation's state (Doc 05 §2.2): what has been
# covered, what to ask next and when to stop all live in state_snapshot, which is
# saved after every turn so a pause, a closed tab or a failed model call never
# loses anything (Doc 08 §24).
class ConversationSession < ApplicationRecord
  belongs_to :company
  belongs_to :engagement
  belongs_to :participant, class_name: "EngagementParticipant", foreign_key: :engagement_participant_id,
                           inverse_of: false
  has_many :turns, -> { order(:turn_index) }, class_name: "ConversationTurn", dependent: :destroy,
                                              inverse_of: :session

  SESSION_TYPES = %w[KEY_PERSON].freeze
  # Doc 08 §6, plus ABANDONED from Doc 06 §4.2 for a session a consultant closes
  # unfinished. NEEDS_CONSULTANT_REVIEW is a flag (needs_review), not a state: a
  # sensitive remark shouldn't stop a conversation with the CEO halfway.
  STATES = %w[NOT_STARTED CONSENT OPENING BROAD_DISCOVERY FOCUSED_EXPLORATION CLARIFICATION PRIORITY_CONFIRMATION
              SCOPE_AND_PARTICIPANTS DOCUMENT_REQUEST COMPLETE PAUSED ABANDONED].freeze
  FINISHED_STATES = %w[COMPLETE ABANDONED].freeze
  # Doc 08 §22, plus ABANDONED (Doc 06 §4.1). The close reason is the engine's
  # main health measure.
  CLOSE_REASONS = %w[COVERAGE_COMPLETE STALLED CEILING PARTICIPANT_ENDED ABANDONED].freeze
  MODALITIES = %w[TEXT MIXED].freeze

  validates :session_type, inclusion: { in: SESSION_TYPES }
  validates :state, inclusion: { in: STATES }
  validates :close_reason, inclusion: { in: CLOSE_REASONS }, allow_nil: true
  validates :modality, inclusion: { in: MODALITIES }
  validate :company_matches_engagement

  scope :key_person, -> { where(session_type: "KEY_PERSON") }

  def finished? = FINISHED_STATES.include?(state)
  def paused? = state == "PAUSED"

  # Moves to a new state and keeps the move (Doc 08 §30 "state transition").
  # Saved with the rest of the turn by the caller.
  def move_to(new_state, at: Time.current)
    raise ArgumentError, "Unknown state #{new_state}" unless STATES.include?(new_state)
    return if state == new_state

    self.state_history = Array(state_history) + [{ "from" => state, "to" => new_state, "at" => at.iso8601 }]
    self.state = new_state
  end

  # The turns a prompt may see as conversation history: system notices (delays,
  # retries) are left out so they can't compound (Doc 05 §3.5).
  def history
    turns.where(is_system_notice: false)
  end

  def next_turn_index
    (turns.maximum(:turn_index) || 0) + 1
  end

  private

  def company_matches_engagement
    errors.add(:company, "must be the engagement's company") if engagement && company_id != engagement.company_id
  end
end
