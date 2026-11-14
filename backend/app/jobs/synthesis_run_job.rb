# frozen_string_literal: true

# Runs consolidation and synthesis for an engagement in the background (Doc 10
# §23), never inside a conversation turn.
#
# Debounced: interviews tend to finish in bursts, so each piece of new
# evidence pushes the queued run back rather than starting another. Only the
# job for the latest request runs; the others find they are early and stop.
# One run per engagement at a time, held by a Postgres advisory lock — a second
# job that cannot take it tries again shortly.
#
# RefreshTaskEvidenceJob reacts to the same interviews for the deep-dive engine.
# The two become one chain when the engines are joined
# (docs/CONSOLIDATION_ENGINES.md §7).
class SynthesisRunJob < ApplicationJob
  queue_as :default

  DEBOUNCE = 10.minutes
  RETRY_LOCKED = 1.minute

  # Asks for a run: joins the queued one if there is one, otherwise queues a new
  # one. wait: 0 for a consultant's "run again", which shouldn't wait.
  def self.request(engagement, trigger:, wait: DEBOUNCE)
    return unless engagement

    run = engagement.with_lock do
      queued = SynthesisRun.find_by(engagement: engagement, status: "QUEUED")
      if queued
        queued.update!(requested_at: Time.current,
                       counts: queued.counts.merge("triggers" => (Array(queued.counts["triggers"]) | [trigger])))
        queued
      else
        SynthesisRun.create!(company: engagement.company, engagement: engagement, trigger: trigger,
                             version: (SynthesisRun.where(engagement: engagement).maximum(:version) || 0) + 1,
                             requested_at: Time.current, counts: { "triggers" => [trigger] })
      end
    end
    set(wait: wait).perform_later(run.id, wait.to_i)
    run
  end

  def perform(run_id, wait_seconds = DEBOUNCE.to_i)
    run = SynthesisRun.find_by(id: run_id)
    return unless run&.status == "QUEUED"
    # A later request queued its own job; that one will run.
    return if run.requested_at > (wait_seconds.seconds.ago + 5.seconds)

    with_engagement_lock(run.engagement_id) do
      Synthesis::Run.call(run)
    end || self.class.set(wait: RETRY_LOCKED).perform_later(run_id, 0)
  rescue StandardError => e
    # The run records the failure; the evidence is safe and the next trigger tries again.
    Rails.logger.error("[SynthesisRunJob] run=#{run_id} #{e.class}: #{e.message}")
  end

  private

  # Yields while holding the engagement's lock; nil without yielding if another
  # run holds it.
  def with_engagement_lock(engagement_id)
    key = Zlib.crc32("synthesis:#{engagement_id}")
    connection = ActiveRecord::Base.connection
    return nil unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")

    begin
      yield
      true
    ensure
      connection.select_value("SELECT pg_advisory_unlock(#{key})")
    end
  end
end
