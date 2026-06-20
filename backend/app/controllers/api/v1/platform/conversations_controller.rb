# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ConversationsController < BaseController
        include Api::V1::MediaAttachmentJson

        def index
          company = ::Company.find(params[:company_id])
          conversations = policy_scope(::Conversation)
            .where(company_id: company.id)
            .includes(:employee)
            .order(updated_at: :desc)

          render json: {
            conversations: conversations.map { |c| conversation_summary(c) }
          }
        end

        def show
          conversation = policy_scope(::Conversation).find(params[:id])
          authorize conversation, :show?

          unless conversation.company_id == params[:company_id].to_i
            return render json: { error: "Not found" }, status: :not_found
          end

          messages = conversation.messages.discovery_only.includes(:media_attachment).order(:created_at)

          render json: {
            conversation: conversation_detail(conversation),
            messages: messages.map { |m| message_json(m) },
            media_attachments: media_attachments_json(
              conversation, namespace: :platform, company_id: conversation.company_id
            )
          }
        end

        private

        def conversation_summary(conversation)
          employee = conversation.employee
          {
            id: conversation.id,
            employee_id: employee.id,
            employee_name: employee.display_name,
            department: employee.department,
            status: conversation.status,
            question_count: conversation.question_count,
            last_activity_at: conversation.last_activity_at
          }
        end

        def conversation_detail(conversation)
          employee = conversation.employee
          conversation_summary(conversation).merge(
            employee_name: employee.display_name || "Employee ##{employee.id}",
            discovery_state: discovery_state_json(conversation, employee)
          )
        end

        def discovery_state_json(conversation, employee)
          blackboard = conversation.blackboard
          {
            profile: blackboard["profile"] || employee.profile_card,
            agent_queue: blackboard["agent_queue"] || [],
            skipped_agents: blackboard["skipped_agents"] || [],
            agent_states: blackboard["agent_states"] || {},
            active_agent_id: blackboard["active_agent_id"],
            coverage: blackboard["coverage"] || {},
            shared_findings: blackboard["shared_findings"] || [],
            conversation_summary: blackboard["conversation_summary"],
            last_routing_decision: conversation.state_snapshot["last_routing_decision"]
          }
        end

        def message_json(message)
          json = {
            id: message.id,
            direction: message.direction,
            message_type: message.message_type,
            body: message.body,
            is_discovery_question: message.is_discovery_question,
            created_at: message.created_at
          }
          if message.media_attachment
            json[:media_attachment] = media_attachment_json(
              message.media_attachment,
              namespace: :platform,
              company_id: params[:company_id]
            )
          end
          json
        end
      end
    end
  end
end
