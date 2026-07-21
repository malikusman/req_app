# frozen_string_literal: true

require "sidekiq/cron/job"

module CatalogSyncSchedule
  module_function

  def interval_hours
    hours = ENV.fetch("AI_CATALOG_SYNC_INTERVAL_HOURS", "12").to_i
    hours = 12 if hours <= 0
    [hours, 168].min # cap at weekly
  end

  def cron_expression
    "0 */#{interval_hours} * * *"
  end

  def apply!(schedule_hash)
    return schedule_hash unless schedule_hash.is_a?(Hash)
    return schedule_hash unless schedule_hash.key?("catalog_sync_all_sources")

    schedule_hash["catalog_sync_all_sources"] = schedule_hash["catalog_sync_all_sources"].merge(
      "cron" => cron_expression
    )
    schedule_hash
  end
end

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  config.on(:startup) do
    schedule_file = Rails.root.join("config/sidekiq_schedule.yml")
    if File.exist?(schedule_file)
      schedule = YAML.load_file(schedule_file)
      # Bang form removes jobs no longer in YAML; destroy_all ensures attribute
      # updates (e.g. active_job: true) replace stale Redis definitions.
      Sidekiq::Cron::Job.destroy_all!
      Sidekiq::Cron::Job.load_from_hash! CatalogSyncSchedule.apply!(schedule)
      Rails.logger.info(
        "[Sidekiq] catalog_sync_all_sources cron=#{CatalogSyncSchedule.cron_expression} " \
        "(AI_CATALOG_SYNC_INTERVAL_HOURS=#{CatalogSyncSchedule.interval_hours})"
      )
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
