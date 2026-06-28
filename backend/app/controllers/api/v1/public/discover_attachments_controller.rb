# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverAttachmentsController < ApplicationController
        include EmployeeWebAuthenticatable

        def create
          Web::TurnRouter.handle_media(
            employee: current_employee,
            conversation: current_conversation,
            file: params[:file],
            caption: params[:caption]
          )

          render json: {
            messages: visible_messages.map { |m| message_json(m) },
            state: state_json
          }
        rescue Web::MediaInboundService::InvalidFile, Web::MediaInboundService::FileTooLarge => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
