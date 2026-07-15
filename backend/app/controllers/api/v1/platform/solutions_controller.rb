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
            :entity_type, :slug, :deployment_model, :maturity, :pricing_summary, :limitations,
            :ownership, :published_at, :last_verified_at,
            tags: [], match_keywords: [], use_cases: [], capabilities: [], required_systems: [],
            industries: [], departments: [], role_relevance: [], security_compliance: [], evidence_urls: []
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
            entity_type: solution.try(:entity_type),
            slug: solution.try(:slug),
            use_cases: solution.try(:use_cases),
            capabilities: solution.try(:capabilities),
            deployment_model: solution.try(:deployment_model),
            maturity: solution.try(:maturity),
            pricing_summary: solution.try(:pricing_summary),
            published_at: solution.try(:published_at),
            last_verified_at: solution.try(:last_verified_at),
            created_at: solution.created_at,
            updated_at: solution.updated_at
          }
        end
      end
    end
  end
end
