# frozen_string_literal: true

class ContinueDiscoveryAfterMediaJob < ApplicationJob
  queue_as :default

  def perform(media_attachment_id)
    attachment = MediaAttachment.find_by(id: media_attachment_id)
    return unless attachment&.status == "ready"
    return unless attachment.message.processing_status == 'ready'

    employee = attachment.employee
    conversation = attachment.conversation
    text = attachment.extracted_text.to_s
    return if text.blank?

    return unless conversation.discovery? || employee.onboarding_step == "verified"

    channel = attachment.message.channel == "web" ? "web" : "whatsapp"
    client = channel == "web" ? Web::CapturingMetaClient.new : Whatsapp::MetaClient.new

    conversation.with_lock do
      source = attachment.message.reload
      unless DiscoveryTurn.exists?(source_message: source)
        DiscoveryRequest.set(admitting: true) do
          Whatsapp::DiscoveryHandler.new(
            employee: employee,
            conversation: conversation,
            client: client,
            channel: channel
          ).process_extracted_text(text, inbound_message: source)
        end
      end
      source.reload.update!(raw_payload: (source.raw_payload || {}).except('discovery_media_pending'))
    end
  end
end
