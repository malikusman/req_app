# frozen_string_literal: true

module Api
  module V1
    module Platform
      class SolutionsController < BaseController
        def index
          solutions = SolutionCatalogEntry.order(:name)
          render json: { solutions: solutions.map { |s| solution_json(s) } }
        end

        def create
          solution = SolutionCatalogEntry.create!(solution_params)
          render json: { solution: solution_json(solution) }, status: :created
        end

        def update
          solution = SolutionCatalogEntry.find(params[:id])
          solution.update!(solution_params)
          render json: { solution: solution_json(solution) }
        end

        private

        def solution_params
          params.require(:solution).permit(
            :name, :vendor, :category, :description, :website_url, :active, :partnership_tier,
            tags: [], match_keywords: []
          )
        end

        def solution_json(solution)
          {
            id: solution.id,
            name: solution.name,
            vendor: solution.vendor,
            category: solution.category,
            description: solution.description,
            website_url: solution.website_url,
            tags: solution.tags,
            match_keywords: solution.match_keywords,
            active: solution.active,
            partnership_tier: solution.partnership_tier,
            created_at: solution.created_at,
            updated_at: solution.updated_at
          }
        end
      end
    end
  end
end
