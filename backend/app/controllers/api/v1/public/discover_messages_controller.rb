# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverMessagesController < ApplicationController
        include EmployeeWebAuthenticatable

        def index
          render json: discovery_response
        end

        def create
          if params[:retry] == true || params[:retry] == "true"
            # Reuse the saved source (including a profiling kickoff); never add
            # another employee message or advance a successfully processed turn.
            pending_turn = DiscoveryTurn.where(conversation: current_conversation).unresolved.order(:source_message_id).first
            source = pending_turn&.source_message || current_conversation.messages.where(direction: "inbound").order(:id).last
            unless current_conversation.status == "discovery" && (pending_turn&.status == "failed" || source&.raw_payload&.key?("discovery_error"))
              return render json: { error: "No saved answer needs retrying" }, status: :conflict
            end
            turn = Discovery::DurableTurn.register(current_conversation, source, source.body)
            current_conversation.with_lock do
              turn.reload
              if turn.status == 'failed'
                turn.update!(status: 'queued', retry_at: nil, attempts: 0)
                source.reload.update!(raw_payload: (source.raw_payload || {}).except('discovery_error').merge('discovery_pending' => true))
                current_conversation.increment!(:discovery_state_version)
              end
            end
            ProcessDiscoveryTurnJob.perform_later(turn.id)

          else
            submission = Discovery::AdmitSubmission.call(conversation: current_conversation, employee: current_employee,
              submission_id: params[:submission_id], body: params[:body])
            @accepted_submission_id = submission.submission_id

          end

          render json: discovery_response(accepted_submission_id: @accepted_submission_id)
        rescue Discovery::AdmitSubmission::Conflict => e
          render json: { error: e.message }, status: :conflict
        end
      end
    end
  end
end
