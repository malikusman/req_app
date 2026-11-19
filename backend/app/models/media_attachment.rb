# frozen_string_literal: true

class MediaAttachment < ApplicationRecord
  after_commit :enqueue_saved_media, if: -> { status == 'pending' && (storage_key.present? || meta_media_id.present?) && (previously_new_record? || saved_change_to_storage_key?) }
  def enqueue_saved_media
    ProcessMediaAttachmentJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[MediaAttachment] enqueue failed media=#{id} error=#{e.class}; sweep will recover")
  end

  belongs_to :message
  belongs_to :company
  belongs_to :employee
  belongs_to :conversation
  belongs_to :document, optional: true

  TYPES = %w[audio image document].freeze
  STATUSES = %w[pending processing ready failed].freeze

  validates :attachment_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
end
