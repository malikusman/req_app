class RecoverDiscoveryTurnsJob < ApplicationJob
  queue_as :default

  def perform
    # Adopt pre-migration recovery records without replaying successful model calls.
    Message.where(direction: 'inbound').where.not(id: DiscoveryTurn.select(:source_message_id)).where(
      "raw_payload -> 'discovery_result' IS NOT NULL OR raw_payload @> ?", { discovery_pending: true }.to_json
    ).find_each do |source|
      Discovery::DurableTurn.register(source.conversation, source, source.body.to_s)
    end
    DiscoveryTurn.where(status: 'queued').or(
      DiscoveryTurn.where(status: 'retry_waiting').where('retry_at IS NULL OR retry_at <= ?', Time.current)
    ).or(DiscoveryTurn.where(status: 'processing').where('lease_until <= ?', Time.current)).find_each do |turn|
      next if DiscoveryTurn.where(conversation_id: turn.conversation_id).unresolved.where('source_message_id < ?', turn.source_message_id).exists?
      ProcessDiscoveryTurnJob.perform_later(turn.id)
    end
    MediaAttachment.where(status: 'pending').where('updated_at < ?', 1.minute.ago).find_each { |media| ProcessMediaAttachmentJob.perform_later(media.id) }
    MediaAttachment.where(status: 'processing').where('updated_at < ?', 2.minutes.ago).find_each { |media| ProcessMediaAttachmentJob.perform_later(media.id) }
    MediaAttachment.joins(:message).where(status: 'ready', messages: { processing_status: 'ready' }).where('media_attachments.updated_at < ?', 1.minute.ago).where("messages.raw_payload @> ?", { discovery_media_pending: true }.to_json).find_each do |media|
      ContinueDiscoveryAfterMediaJob.perform_later(media.id)
    end
    # Also cover a crash between an old successful result and reply persistence.
    DiscoveryTurn.where(status: 'succeeded', reply_message_id: nil).find_each do |turn|
      Discovery::DurableTurn.deliver(turn)
    end
    Message.where(delivery_status: 'processing').where('delivery_lease_until <= ?', Time.current).update_all(delivery_status: 'uncertain')
    Message.where(delivery_status: 'pending').where(
      'delivery_lease_until IS NULL OR delivery_lease_until <= ?', Time.current
    ).find_each { |message| DeliverDiscoveryReplyJob.perform_later(message.id) }
  end
end
