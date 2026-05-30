# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class AgentInterruptsController < BaseController
        before_action :set_company

        def index
          interrupts = @company.agent_interrupts.pending.order(created_at: :desc)
          render json: { interrupts: interrupts.map { |i| interrupt_json(i) } }
        end

        def update
          interrupt = @company.agent_interrupts.find(params[:id])
          Agents::ResolveInterruptService.call(
            interrupt: interrupt,
            resolver: current_reviewer_user,
            action: params.require(:action),
            edited_message: params[:edited_message]
          )
          render json: { interrupt: interrupt_json(interrupt.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def set_company
          @company = Company.find(params[:company_id])
          authorize @company, :show?
        end

        def interrupt_json(interrupt)
          {
            id: interrupt.id,
            kind: interrupt.kind,
            status: interrupt.status,
            payload: interrupt.payload,
            resolution: interrupt.resolution,
            thread_id: interrupt.thread_id,
            employee_id: interrupt.employee_id,
            conversation_id: interrupt.conversation_id,
            created_at: interrupt.created_at,
            resolved_at: interrupt.resolved_at
          }
        end
      end
    end
  end
end
