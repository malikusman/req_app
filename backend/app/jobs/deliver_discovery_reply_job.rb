class DeliverDiscoveryReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message
    token = SecureRandom.uuid
    claimed = message.with_lock do
      next false if %w[sent uncertain].include?(message.delivery_status) || (message.delivery_lease_until && message.delivery_lease_until > Time.current)
      message.update!(delivery_status: 'processing', delivery_token: token, delivery_lease_until: 45.seconds.from_now)
      true
    end
    return unless claimed
    employee = message.conversation.employee
    client = Whatsapp::MetaClient.new
    client.send_text(to: employee.phone_e164, body: message.body) if client.configured?
    message.with_lock do
      message.update!(delivery_status: 'sent', delivery_lease_until: nil) if message.delivery_token == token
    end
  rescue StandardError
    message&.with_lock do
      message.update!(delivery_status: 'uncertain', delivery_lease_until: nil) if message.delivery_token == token
    end
    raise
  end
end
