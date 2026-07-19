# frozen_string_literal: true

module Api
  module V1
    module Platform
      class CompanySystemsController < BaseController
        before_action :set_company

        def index
          systems = @company.company_systems.order(:name)
          render json: { company_systems: systems.map { |s| system_json(s) } }
        end

        def create
          system = @company.company_systems.create!(system_params.merge(source: "manual", confidence: 1.0))
          render json: { company_system: system_json(system) }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end

        def update
          system = @company.company_systems.find(params[:id])
          system.update!(system_params)
          render json: { company_system: system_json(system) }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end

        def destroy
          system = @company.company_systems.find(params[:id])
          system.update!(active: false)
          render json: { company_system: system_json(system) }
        end

        def infer
          count = Intelligence::CompanyStackInferrer.call(company: @company).size
          systems = @company.company_systems.order(:name)
          render json: { inferred: count, company_systems: systems.map { |s| system_json(s) } }
        end

        private

        def set_company
          @company = ::Company.find(params[:company_id])
        end

        def system_params
          params.require(:company_system).permit(:name, :category, :notes, :active, :confidence)
        end

        def system_json(s)
          {
            id: s.id,
            name: s.name,
            category: s.category,
            source: s.source,
            confidence: s.confidence,
            active: s.active,
            notes: s.notes,
            created_at: s.created_at,
            updated_at: s.updated_at
          }
        end
      end
    end
  end
end
