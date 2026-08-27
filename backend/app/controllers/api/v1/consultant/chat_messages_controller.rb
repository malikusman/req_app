# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ChatMessagesController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize ConsultantChatMessage.new(company: company), :index?

          messages = ConsultantChatMessage.where(company_id: company.id).order(:created_at).includes(:sender_consultant_user)
          render json: {
            messages: messages.map { |m|
              {
                id: m.id,
                body: m.body,
                sender_consultant_user_id: m.sender_consultant_user_id,
                sender_name: m.sender_consultant_user.name,
                created_at: m.created_at,
                mine: m.sender_consultant_user_id == current_consultant_user.id
              }
            }
          }
        end

        def create
          company = policy_scope(::Company).find(params[:company_id])
          message = ConsultantChatMessage.new(company: company, sender_consultant_user: current_consultant_user, body: params.require(:body))
          authorize message, :create?
          message.save!

          other_ids = company.consultant_assignments.active.pluck(:consultant_user_id) - [current_consultant_user.id]
          ConsultantUser.where(id: other_ids).find_each do |consultant|
            NotificationService.notify_consultant_chat_message(
              recipient: consultant,
              company: company,
              sender: current_consultant_user
            )
          end

          render json: { message: { id: message.id, body: message.body, created_at: message.created_at } }, status: :created
        end
      end
    end
  end
end
