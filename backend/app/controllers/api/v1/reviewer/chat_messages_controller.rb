# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ChatMessagesController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize ReviewerChatMessage.new(company: company), :index?

          messages = ReviewerChatMessage.where(company_id: company.id).order(:created_at).includes(:sender_reviewer_user, :sender_platform_user)
          render json: {
            messages: messages.map { |m| message_json(m) }
          }
        end

        def create
          company = policy_scope(::Company).find(params[:company_id])
          message = ReviewerChatMessage.new(
            company: company,
            sender_reviewer_user: current_reviewer_user,
            sender_role: "reviewer",
            body: params[:body].presence || attachment_caption(params[:file])
          )
          attach_file!(message, params[:file]) if params[:file].respond_to?(:read)
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

          render json: { message: message_json(message) }, status: :created
        end

        private

        def message_json(message)
          {
            id: message.id,
            body: message.body,
            sender_reviewer_user_id: message.sender_reviewer_user_id,
            sender_role: message.sender_role,
            sender_name: message.sender_name,
            created_at: message.created_at,
            mine: message.sender_role == "reviewer" && message.sender_reviewer_user_id == current_reviewer_user.id,
            attachment: message.attachment_storage_key.present? ? {
              filename: message.attachment_filename,
              content_type: message.attachment_content_type,
              byte_size: message.attachment_byte_size
            } : nil
          }
        end

        def attach_file!(message, file)
          filename = file.original_filename.presence || "attachment.bin"
          storage_key = "reviewer_chat/#{message.company_id}/#{SecureRandom.uuid}/#{filename}"
          body = file.read
          Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: file.content_type)

          message.attachment_filename = filename
          message.attachment_content_type = file.content_type
          message.attachment_byte_size = body.bytesize
          message.attachment_storage_key = storage_key
        end

        def attachment_caption(file)
          return "Shared a file" unless file.respond_to?(:original_filename)

          "Shared file: #{file.original_filename}"
        end
      end
    end
  end
end
