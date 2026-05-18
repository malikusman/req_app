# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ChatMessagesController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize ReviewerChatMessage.new(company: company), :index?

          messages = ReviewerChatMessage.where(company_id: company.id).order(:created_at).includes(:sender_reviewer_user)
          render json: {
            messages: messages.map { |m|
              {
                id: m.id,
                body: m.body,
                sender_reviewer_user_id: m.sender_reviewer_user_id,
                sender_name: m.sender_reviewer_user.name,
                created_at: m.created_at,
                mine: m.sender_reviewer_user_id == current_reviewer_user.id
              }
            }
          }
        end

        def create
          company = policy_scope(::Company).find(params[:company_id])
          message = ReviewerChatMessage.new(company: company, sender_reviewer_user: current_reviewer_user, body: params.require(:body))
          authorize message, :create?
          message.save!

          other_ids = company.reviewer_assignments.active.pluck(:reviewer_user_id) - [current_reviewer_user.id]
          ReviewerUser.where(id: other_ids).find_each do |reviewer|
            NotificationService.notify_reviewer_chat_message(
              recipient: reviewer,
              company: company,
              sender: current_reviewer_user
            )
          end

          render json: { message: { id: message.id, body: message.body, created_at: message.created_at } }, status: :created
        end
      end
    end
  end
end
