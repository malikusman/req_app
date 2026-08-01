# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      # Reviewer visibility into a company's owned/in-house solutions, and the
      # ability to endorse (or annotate) their relevance to the report.
      class OwnedSolutionsController < BaseController
        before_action :load_company

        def index
          solutions = @company.company_systems.owned_solutions.order(:name)
          render json: { owned_solutions: solutions.map { |s| serialize(s) } }
        end

        def endorse
          solution = @company.company_systems.owned_solutions.find(params[:id])
          solution.update!(
            reviewer_endorsed: ActiveModel::Type::Boolean.new.cast(params[:reviewer_endorsed]),
            reviewer_note: params[:reviewer_note].presence,
            reviewer_user: current_reviewer_user
          )
          render json: { owned_solution: serialize(solution) }
        end

        private

        def load_company
          @company = policy_scope(::Company).find(params[:company_id])
        end

        def serialize(s)
          {
            id: s.id,
            name: s.name,
            category: s.category,
            description: s.description,
            capabilities: s.capabilities,
            reviewer_endorsed: s.reviewer_endorsed,
            reviewer_note: s.reviewer_note,
            reviewer_name: s.reviewer_user&.name
          }
        end

        # Small boolean coercion helper (params come in as strings).
        module ActivemodelBoolean
          def self.cast(value)
            ActiveModel::Type::Boolean.new.cast(value)
          end
        end
      end
    end
  end
end
