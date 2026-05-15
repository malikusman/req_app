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
      html = HtmlBuilder.call(snapshot: snapshot)
      pdf_bytes = PdfGenerator.call(html: html)

      content_type = pdf_bytes == html ? "text/html" : "application/pdf"
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
        error_message: nil
      )

      visibility = @company.merged_settings["skip_platform_review"] ? "shared_with_company" : @report.visibility
      @report.update!(visibility: visibility) if @report.triggered_by_type == "CompanyUser"

      NotificationService.notify_report_ready(company: @company, report: @report)
      @report
    rescue StandardError => e
      @report.update!(status: "failed", error_message: e.message)
      raise
    end
  end
end
