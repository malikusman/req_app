# frozen_string_literal: true

module Reports
  # The consultant mints the next report version when new evidence has landed.
  #
  # Evidence does not stop arriving when a report is reviewed: more interviews
  # complete, documents get analysed, signals strengthen. Until now the only way
  # to fold that in was for the COMPANY to click Generate — which is backwards,
  # because the consultant is the one who knows whether new evidence actually
  # changes the advice.
  #
  # Deliberately a new VERSION rather than a re-render of the current one:
  #   * DeltaCalculator then states what changed since the version the client
  #     already has, which is the whole point of resharing;
  #   * the previous version stays on the record as what was approved;
  #   * carry_forward_overrides! copies the consultant's published edits onto the
  #     new version, so re-review starts from their work, not from scratch.
  class ConsultantRefreshService
    class NotStale < StandardError; end

    def self.call(report:, consultant_user:, force: false)
      new(report: report, consultant_user: consultant_user, force: force).call
    end

    def initialize(report:, consultant_user:, force: false)
      @report = report
      @company = report.company
      @consultant_user = consultant_user
      @force = force
    end

    def call
      raise NotStale, "A report is already generating for this company." if in_flight?

      unless @force || stale?
        raise NotStale, "No new evidence since this report was generated. Nothing to refresh."
      end

      previous = @company.reports.ready.order(version: :desc).first
      report = @company.reports.create!(
        version: (@company.reports.maximum(:version) || 0) + 1,
        status: "queued",
        # Held back from the company until it is reviewed and approved again —
        # the same gate every other generated report goes through. A consultant
        # refreshing a report does not get to skip their own review.
        visibility: "internal_only",
        triggered_by_type: "ConsultantUser",
        triggered_by_id: @consultant_user.id,
        previous_report: previous
      )

      GenerateReportJob.perform_later(report.id)
      { report: report, stale: stale? }
    end

    private

    def in_flight?
      @company.reports.where(status: %w[queued generating]).exists?
    end

    # Same staleness test the company portal shows as "report stale", so the two
    # surfaces can never disagree about whether there is anything new.
    def stale?
      intel_at = @company.intelligence_updated_at
      return false if intel_at.blank?

      generated_at = @report.generated_at || @report.created_at
      intel_at > generated_at
    end
  end
end
