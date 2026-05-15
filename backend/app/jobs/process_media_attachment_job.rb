# frozen_string_literal: true

class ProcessMediaAttachmentJob < ApplicationJob
  queue_as :default

  def perform(media_attachment_id)
    Multimodal::ProcessMediaService.call(media_attachment_id)
  end
end
