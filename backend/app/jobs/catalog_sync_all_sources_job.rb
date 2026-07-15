# frozen_string_literal: true

# Cron cadence is derived from AI_CATALOG_SYNC_INTERVAL_HOURS (default 12) in
# config/initializers/sidekiq.rb. This job also skips sources synced more recently
# than that interval (manual sync still forces via SyncSourceService directly).
class CatalogSyncAllSourcesJob < ApplicationJob
  queue_as :default

  def perform(force: false)
    interval = defined?(CatalogSyncSchedule) ? CatalogSyncSchedule.interval_hours.hours : 12.hours

    CatalogSource.active.find_each do |source|
      if !force && source.last_sync_at.present? && source.last_sync_at > interval.ago
        Rails.logger.info("[CatalogSyncAllSourcesJob] skip source=#{source.id} last_sync_at=#{source.last_sync_at}")
        next
      end

      Catalog::SyncSourceService.call(catalog_source: source)
    rescue StandardError => e
      Rails.logger.error("[CatalogSyncAllSourcesJob] source=#{source.id} failed: #{e.message}")
    end
  end
end
