# frozen_string_literal: true

class ProcessMediaAttachmentJob < ApplicationJob
  queue_as :default

  def perform(media_attachment_id)
    # Nonblocking session lock: a sweep and an old Sidekiq retry may coexist.
    # PostgreSQL releases ownership automatically when a crashed worker exits.
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      key = -1_000_000_000_000 - Integer(media_attachment_id)
      acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      return unless acquired
      begin
        Multimodal::ProcessMediaService.call(media_attachment_id)
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
