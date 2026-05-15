# frozen_string_literal: true

class ContinueDiscoveryAfterMediaJob < ApplicationJob
  queue_as :default

  def perform(media_attachment_id)
    attachment = MediaAttachment.find_by(id: media_attachment_id)
    return unless attachment&.status == "ready"

    employee = attachment.employee
    conversation = attachment.conversation
    text = attachment.extracted_text.to_s
    return if text.blank?

    return unless conversation.discovery? || employee.onboarding_step == "verified"

    Whatsapp::DiscoveryHandler.new(employee: employee, conversation: conversation)
                               .process_extracted_text(text, inbound_message: attachment.message)
  end
end
