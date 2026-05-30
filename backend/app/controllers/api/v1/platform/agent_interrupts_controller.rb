# frozen_string_literal: true

module Api
  module V1
    module Platform
      class AgentInterruptsController < BaseController
        def index
          interrupts = AgentInterrupt.pending.includes(:company, :employee).order(created_at: :desc).limit(100)
          render json: { interrupts: interrupts.map { |i| interrupt_json(i) } }
        end

        def update
          interrupt = AgentInterrupt.find(params[:id])
          Agents::ResolveInterruptService.call(
            interrupt: interrupt,
            resolver: current_platform_user,
            action: params.require(:action),
            edited_message: params[:edited_message]
          )
          render json: { interrupt: interrupt_json(interrupt.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def interrupt_json(interrupt)
          {
            id: interrupt.id,
            company_id: interrupt.company_id,
            company_name: interrupt.company.name,
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
