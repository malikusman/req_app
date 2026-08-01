# frozen_string_literal: true

module Api
  module V1
    module Company
      # Company self-service for owned / in-house solutions (e.g. "our HR agentic
      # AI", "a compliance app we built"). These carry a description + capabilities
      # and are scored for fit against the frictions the engagement surfaced.
      class CompanySystemsController < BaseController
        def index
          solutions = current_company.company_systems.owned_solutions.order(:name)
          render json: { owned_solutions: solutions.map { |s| serialize(s) } }
        end

        def create
          solution = current_company.company_systems.new(create_params)
          solution.assign_attributes(kind: "owned_solution", source: "manual", confidence: 1.0, active: true)
          solution.save!
          render json: { owned_solution: serialize(solution) }, status: :created
        end

        def update
          solution = owned.find(params[:id])
          solution.update!(update_params)
          render json: { owned_solution: serialize(solution) }
        end

        def destroy
          owned.find(params[:id]).update!(active: false)
          head :no_content
        end

        private

        def owned
          current_company.company_systems.owned_solutions
        end

        def create_params
          params.require(:owned_solution).permit(:name, :category, :description, :capabilities)
        end

        def update_params
          params.require(:owned_solution).permit(:name, :category, :description, :capabilities, :active)
        end

        def serialize(s)
          {
            id: s.id,
            name: s.name,
            category: s.category,
            description: s.description,
            capabilities: s.capabilities,
            active: s.active,
            reviewer_endorsed: s.reviewer_endorsed,
            reviewer_note: s.reviewer_note
          }
        end
      end
    end
  end
end
