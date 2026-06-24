# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverMessagesController < ApplicationController
        include EmployeeWebAuthenticatable

        def index
          render json: {
            messages: visible_messages.map { |m| message_json(m) },
            state: state_json
          }
        end

        def create
          Web::TurnRouter.handle_text(
            employee: current_employee,
            conversation: current_conversation,
            text: params[:body]
          )

          render json: {
            messages: visible_messages.map { |m| message_json(m) },
            state: state_json
          }
        end
      end
    end
  end
end
