# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverAttachmentsController < ApplicationController
        include EmployeeWebAuthenticatable

        def create
          submission = Discovery::AdmitSubmission.call(conversation: current_conversation, employee: current_employee,
            submission_id: params[:submission_id], body: params[:caption], file: params[:file])

          render json: discovery_response(accepted_submission_id: submission.submission_id)
        rescue Discovery::AdmitSubmission::Conflict => e
          render json: { error: e.message }, status: :conflict
        rescue Web::MediaInboundService::InvalidFile, Web::MediaInboundService::FileTooLarge => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
