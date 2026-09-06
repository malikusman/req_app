# frozen_string_literal: true

module Api
  module V1
    module DiscoveryConversationJson
      extend ActiveSupport::Concern

      private

      # What the interview learned and what it still wanted, for the provenance view.
      # Replaces the specialist queue's agent_queue / agent_states / topic coverage,
      # which described an engine that no longer exists.
      def discovery_state_json(conversation, employee)
        blackboard = conversation.blackboard
        dossier = blackboard["dossier"] || {}
        {
          profile: blackboard["profile"] || employee.profile_card,
          role_areas: blackboard["role_areas"] || [],
          slots: dossier["slots"] || {},
          parked: dossier["parked"] || [],
          close_reason: blackboard["close_reason"],
          stall_turns: blackboard["stall_turns"].to_i,
          shared_findings: blackboard["shared_findings"] || [],
          conversation_summary: blackboard["conversation_summary"],
          last_routing_decision: blackboard["last_routing_decision"] ||
            conversation.state_snapshot["last_routing_decision"]
        }
      end

      def discovery_provenance_json(messages)
        messages.filter_map do |message|
          next unless message.direction == "outbound"
          next unless message.agent_id.present? || message.routing_decision.present?

          {
            message_id: message.id,
            agent_id: message.agent_id,
            routing_decision: message.routing_decision.presence,
            is_discovery_question: message.is_discovery_question,
            created_at: message.created_at,
            body_preview: message.body.to_s.truncate(120)
          }
        end
      end

      def message_provenance_fields(message)
        fields = {}
        fields[:agent_id] = message.agent_id if message.agent_id.present?
        fields[:routing_decision] = message.routing_decision if message.routing_decision.present?
        fields
      end
    end
  end
end
