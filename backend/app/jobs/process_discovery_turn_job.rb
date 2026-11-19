class ProcessDiscoveryTurnJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = DiscoveryTurn.find_by(id: turn_id)
    return unless turn
    return if %w[failed superseded].include?(turn.status)
    Discovery::ProcessTurnService.call(conversation: turn.conversation, employee: turn.conversation.employee,
      user_message: turn.user_message, inbound_message: turn.source_message, defer_on_failure: false)
  end
end
