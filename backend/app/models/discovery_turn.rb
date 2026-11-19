class DiscoveryTurn < ApplicationRecord
  belongs_to :reply_message, class_name: 'Message', optional: true
  belongs_to :conversation
  belongs_to :source_message, class_name: 'Message'
  ACTIVE = %w[queued processing retry_waiting failed].freeze
  scope :unresolved, -> { where(status: ACTIVE) }
  after_create_commit :enqueue_processing

  def enqueue_processing
    ProcessDiscoveryTurnJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[DiscoveryTurn] enqueue failed turn=#{id} error=#{e.class}; sweep will recover")
  end
end
