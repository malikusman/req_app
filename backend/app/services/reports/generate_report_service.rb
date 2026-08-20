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
      html = HtmlBuilder.call(snapshot: snapshot, report_version: @report.version)
      pdf_bytes = PdfGenerator.call(html: html)
      html_fallback = pdf_bytes == html
      content_type = html_fallback ? "text/html" : "application/pdf"
      ext = content_type == "application/pdf" ? "pdf" : "html"
      storage_key = "reports/#{@company.id}/v#{@report.version}/report.#{ext}"

      Storage::MinioClient.new.upload(
        key: storage_key,
        body: pdf_bytes,
        content_type: content_type
      )

      @report.update!(
        status: "ready",
        storage_key: storage_key,
        content_type: content_type,
        report_snapshot: snapshot,
        generated_at: Time.current,
        error_message: html_fallback ? "PDF service unavailable — stored as HTML (not a PDF)." : nil
      )

      carry_forward_overrides!(previous)

      # Enforce the review/approval GATE. A ready report is never auto-shipped to
      # the company; it becomes downloadable only after platform approval (via a
      # reviewer when assigned), unless the company is explicitly skip_platform_review.
      if @company.merged_settings["skip_platform_review"]
        @report.update!(visibility: "shared_with_company", review_workflow_status: "platform_approved")
        NotificationService.notify_report_ready(company: @company, report: @report)
      elsif @company.reviewer_assignments.active.exists?
        ReportReviews::BootstrapService.call(report: @report) # → internal_only + awaiting_reviewers, notifies reviewers
        NotificationService.notify_report_in_review(company: @company, report: @report)
      else
        # No reviewer assigned — still gated behind platform approval, not shipped.
        @report.update!(visibility: "internal_only", review_workflow_status: "reviews_complete")
        NotificationService.notify_platform_report_awaiting_approval(company: @company, report: @report)
      end

      @report
    rescue StandardError => e
      @report.update!(status: "failed", error_message: e.message)
      raise
    end

    private

    # Reviewer edits are per-report, so a new version would otherwise lose the
    # expert's hides / notes / added / replaced sections. Copy the previous
    # version's published overrides onto the new one as a starting point (the
    # reviewer re-reviews the new version and can adjust).
    def carry_forward_overrides!(previous)
      return unless previous
      return unless defined?(ReportSectionOverride) && ReportSectionOverride.table_exists?
      return if @report.report_section_overrides.exists?

      previous.report_section_overrides.published.find_each do |ov|
        @report.report_section_overrides.create!(
          reviewer_user_id: ov.reviewer_user_id,
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
