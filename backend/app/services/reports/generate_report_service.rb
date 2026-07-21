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

      if @company.reviewer_assignments.active.exists?
        ReportReviews::BootstrapService.call(report: @report)
      elsif @company.merged_settings["skip_platform_review"]
        @report.update!(visibility: "shared_with_company", review_workflow_status: "platform_approved")
      end

      NotificationService.notify_report_ready(company: @company, report: @report)
      @report
    rescue StandardError => e
      @report.update!(status: "failed", error_message: e.message)
      raise
    end
  end
end
