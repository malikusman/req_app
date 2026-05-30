# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReviewerChatController < BaseController
        def index
          company = ::Company.find(params[:company_id])
          messages = ReviewerChatMessage.where(company_id: company.id)
            .order(:created_at)
            .includes(:sender_reviewer_user, :sender_platform_user)

          render json: {
            messages: messages.map { |m|
              {
                id: m.id,
                body: m.body,
                sender_name: m.sender_name,
                sender_role: m.sender_role,
                created_at: m.created_at,
                attachment: m.attachment_storage_key.present? ? {
                  filename: m.attachment_filename,
                  content_type: m.attachment_content_type,
                  byte_size: m.attachment_byte_size
                } : nil
              }
            }
          }
        end

        def create
          company = ::Company.find(params[:company_id])
          message = ReviewerChatMessage.new(
            company: company,
            sender_platform_user: current_platform_user,
            sender_role: "platform",
            body: params[:body].presence || "Platform admin shared an update"
          )
          attach_file!(message, params[:file]) if params[:file].respond_to?(:read)
          authorize message, :create?
          message.save!

          render json: {
            message: {
              id: message.id,
              body: message.body,
              sender_name: message.sender_name,
              sender_role: message.sender_role,
              created_at: message.created_at
            }
          }, status: :created
        end

        private

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
      end
    end
  end
end
