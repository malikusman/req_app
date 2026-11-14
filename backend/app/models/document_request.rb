# frozen_string_literal: true

# A specific document asked for at the end of a conversation, in the words the
# participant used (Doc 06 §4.4). Uploads are optional and never block anything
# (Doc 14 §11.4); one the participant can't or won't share is closed, and isn't
# asked for again.
class DocumentRequest < ApplicationRecord
  STATUSES = %w[REQUESTED RECEIVED DECLINED NOT_AVAILABLE].freeze

  belongs_to :company
  belongs_to :session, class_name: "ConversationSession", foreign_key: :conversation_session_id, inverse_of: false
  has_many :documents, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :requested_item, :reason, presence: true

  scope :open, -> { where(status: "REQUESTED") }
end
