# frozen_string_literal: true

# Interval note: schedule cadence mirrors AI_CATALOG_SYNC_INTERVAL_HOURS (default 12).
# Sidekiq cron is configured in sidekiq_schedule.yml; override ENV when changing ops cadence.
class CatalogSyncAllSourcesJob < ApplicationJob
  queue_as :default

  def perform
    CatalogSource.active.find_each do |source|
      Catalog::SyncSourceService.call(catalog_source: source)
    rescue StandardError => e
      Rails.logger.error("[CatalogSyncAllSourcesJob] source=#{source.id} failed: #{e.message}")
    end
  end
end
