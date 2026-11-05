# frozen_string_literal: true

# One thing said in a conversation (Doc 06 §4.3): by the assistant, by the
# participant, or a system notice. The text is kept as said, in the original
# language. A participant's turn is the evidence that everything captured from
# it cites, by its locator ("t7").
class ConversationTurn < ApplicationRecord
  belongs_to :session, class_name: "ConversationSession", foreign_key: :conversation_session_id, inverse_of: :turns

  DIRECTIONS = %w[AI PARTICIPANT SYSTEM].freeze
  INPUT_MODES = %w[TEXT VOICE_NOTE].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :input_mode, inclusion: { in: INPUT_MODES }
  validates :text, presence: true
  validates :turn_index, presence: true, uniqueness: { scope: :conversation_session_id }

  scope :from_participant, -> { where(direction: "PARTICIPANT") }
  scope :from_assistant, -> { where(direction: "AI") }

  def locator = "t#{turn_index}"
  def participant? = direction == "PARTICIPANT"
  def assistant? = direction == "AI"
end
