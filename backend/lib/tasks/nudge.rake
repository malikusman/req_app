# frozen_string_literal: true

namespace :nudge do
  desc "Backfill legacy nudge statuses and re-queue stuck deliveries"
  task repair: :environment do
    SendEmployeeNudgeJob.backfill_legacy_statuses!
    puts "Backfilled legacy nudge statuses"

    stuck = EmployeeNudge.where(delivery_status: "queued", whatsapp_status: "queued")
                         .where("created_at < ?", 2.minutes.ago)
    count = stuck.count
    stuck.find_each { |nudge| SendEmployeeNudgeJob.perform_later(nudge.id) }
    puts "Re-queued #{count} stuck nudge(s)"
  end
end
