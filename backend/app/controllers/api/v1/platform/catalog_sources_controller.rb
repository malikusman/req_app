# frozen_string_literal: true

module Api
  module V1
    module Platform
      class CatalogSourcesController < BaseController
        def index
          sources = CatalogSource.order(:name)
          render json: {
            catalog_sources: sources.map { |s| source_json(s) },
            sync_interval_hours: defined?(CatalogSyncSchedule) ? CatalogSyncSchedule.interval_hours : 12
          }
        end

        def create
          source = CatalogSource.create!(source_params)
          render json: { catalog_source: source_json(source) }, status: :created
        end

        def update
          source = CatalogSource.find(params[:id])
          source.update!(source_params)
          render json: { catalog_source: source_json(source) }
        end

        def destroy
          source = CatalogSource.find(params[:id])
          source.destroy!
          head :no_content
        end

        def sync
          source = CatalogSource.find(params[:id])
          run = Catalog::SyncSourceService.call(catalog_source: source)
          render json: {
            catalog_source: source_json(source.reload),
            catalog_sync_run: {
              id: run.id,
              status: run.status,
              records_fetched: run.records_fetched,
              candidates_created: run.candidates_created,
              errors: run.error_details
            }
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def source_params
          params.require(:catalog_source).permit(
            :name, :source_type, :endpoint_url, :sync_cron, :trust_score, :active, config: {}
          )
        end

        def source_json(s)
          {
            id: s.id,
            name: s.name,
            source_type: s.source_type,
            endpoint_url: s.endpoint_url,
            sync_cron: s.sync_cron,
            last_sync_at: s.last_sync_at,
            last_sync_status: s.last_sync_status,
            trust_score: s.trust_score,
            active: s.active,
            config: s.config,
            created_at: s.created_at,
            updated_at: s.updated_at
          }
        end
      end
    end
  end
end
