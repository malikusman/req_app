# frozen_string_literal: true

module Reports
  class GenerateReportService
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
      @company = report.company
    end

    def call
      @report.update!(status: "generating")

      previous = @report.previous_report
      delta = DeltaCalculator.call(company: @company, previous_report: previous)
      snapshot = SnapshotBuilder.call(company: @company, delta: delta)
      # One snapshot, N renderings. A variant is a section allowlist and a paper
      # size — never a second analysis — so the brief and the full report cannot
      # disagree about a number.
      VariantSpec::VARIANTS.each do |variant|
        html = HtmlBuilder.call(snapshot: snapshot, report_version: @report.version, variant: variant)
        ArtifactWriter.call(report: @report, variant: variant, html: html)
      end

      @report.update!(
        status: "ready",
        report_snapshot: snapshot,
        generated_at: Time.current
      )

      carry_forward_overrides!(previous)

      # Enforce the review/approval GATE. A ready report is never auto-shipped to
      # the company; it becomes downloadable only after platform approval (via a
      # consultant when assigned), unless the company is explicitly skip_platform_review.
      if @company.merged_settings["skip_platform_review"]
        @report.update!(visibility: "shared_with_company", review_workflow_status: "platform_approved")
        NotificationService.notify_report_ready(company: @company, report: @report)
      elsif @company.consultant_assignments.active.exists?
        ReportReviews::BootstrapService.call(report: @report) # → internal_only + awaiting_consultants, notifies consultants
        NotificationService.notify_report_in_review(company: @company, report: @report)
      else
        # No consultant assigned — still gated behind platform approval, not shipped.
        @report.update!(visibility: "internal_only", review_workflow_status: "reviews_complete")
        NotificationService.notify_platform_report_awaiting_approval(company: @company, report: @report)
      end

      @report
    rescue StandardError => e
      @report.update!(status: "failed", error_message: e.message)
      raise
    end

    private

    # Consultant edits are per-report, so a new version would otherwise lose the
    # expert's hides / notes / added / replaced sections. Copy the previous
    # version's published overrides onto the new one as a starting point (the
    # consultant re-reviews the new version and can adjust).
    def carry_forward_overrides!(previous)
      return unless previous
      return unless defined?(ReportSectionOverride) && ReportSectionOverride.table_exists?
      return if @report.report_section_overrides.exists?

      # Deduped: without this, a section the consultant re-added after it had
      # already been carried forward accumulates a fresh copy on every version,
      # and the report prints the page once per copy.
      seen = Set.new
      previous.report_section_overrides.published.find_each do |ov|
        signature = [ov.action, ov.section_key, ov.title.to_s.strip, ov.body.to_s.strip]
        next unless seen.add?(signature)

        @report.report_section_overrides.create!(
          consultant_user_id: ov.consultant_user_id,
          action: ov.action,
          section_key: ov.section_key,
          anchor_section: ov.anchor_section,
          title: ov.title,
          body: ov.body,
          position: ov.position,
          published: true
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[GenerateReportService] carry_forward_overrides skipped: #{e.class}: #{e.message}")
    end
  end
end
