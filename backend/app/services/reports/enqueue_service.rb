# frozen_string_literal: true

module Reports
  # The one way a report gets onto the queue.
  #
  # Generation used to have no reachable entry point at all: the company-facing
  # endpoint was refused by policy, the consultant's refresh had no caller, and
  # the platform had nothing. Every report in existence came from a rake task.
  # This is the shared primitive behind the consultant and platform actions that
  # replaced that.
  #
  # Always a new VERSION, never a re-render of the current one:
  #   * DeltaCalculator can then state what changed since the version the client
  #     already has, which is the whole point of re-sharing;
  #   * the previous version stays on the record as the thing that was approved;
  #   * GenerateReportService carries the consultant's published edits forward,
  #     so re-review starts from their work rather than from scratch.
  #
  # It never ships anything. The new version is held at internal_only and goes
  # through consultant review and platform approval like any other — a consultant
  # regenerating does not get to skip their own review, and the client keeps the
  # version they already have until the new one is approved.
  class EnqueueService
    # Two different refusals, because they need two different answers from the
    # caller: wait, versus you have nothing new to say.
    class Busy < StandardError; end
    class NotStale < StandardError; end

    # Past this, a report that still says "generating" is not generating — the
    # worker died. Without the window, one crashed job locks a company out of
    # report generation permanently, with "already generating" as the only
    # explanation and the console as the only fix. Generation runs in about two
    # minutes, so an hour is far outside any honest run.
    IN_FLIGHT_WINDOW = 1.hour

    def self.call(company:, triggered_by:, force: false)
      new(company: company, triggered_by: triggered_by, force: force).call
    end

    def initialize(company:, triggered_by:, force: false)
      @company = company
      @triggered_by = triggered_by
      @force = force
    end

    def call
      raise Busy, "A report is already generating for this company." if in_flight?

      # Staleness only means something once there is a report to be stale
      # against. The first one is always allowed.
      if latest && !@force && !stale?
        raise NotStale, "No new evidence since the last report. Generate anyway to re-cut it."
      end

      report = @company.reports.create!(
        version: (@company.reports.maximum(:version) || 0) + 1,
        status: "queued",
        visibility: "internal_only",
        triggered_by_type: @triggered_by.class.name,
        triggered_by_id: @triggered_by.id,
        previous_report: latest_ready
      )

      GenerateReportJob.perform_later(report.id)
      { report: report, stale: stale?, first: latest.nil? }
    end

    private

    def in_flight?
      @company.reports
              .where(status: %w[queued generating])
              .where(created_at: IN_FLIGHT_WINDOW.ago..)
              .exists?
    end

    def latest
      return @latest if defined?(@latest)

      @latest = @company.reports.order(version: :desc).first
    end

    # The delta is only meaningful against a version that actually rendered.
    def latest_ready
      @latest_ready ||= @company.reports.ready.order(version: :desc).first
    end

    # The same staleness test the company portal shows as "report stale", so the
    # surfaces can never disagree about whether there is anything new.
    def stale?
      return false if latest.nil?

      intel_at = @company.intelligence_updated_at
      return false if intel_at.blank?

      intel_at > (latest.generated_at || latest.created_at)
    end
  end
end
