# frozen_string_literal: true

module Reports
  # Re-renders and uploads the report artifact, merging submitted reviewer notes into the PDF appendix.
  class RegenerateWithReviewService
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
      @company = report.company
    end

    def call
      raise ArgumentError, "Report not ready" unless @report.status == "ready"
      raise ArgumentError, "Report snapshot missing" if @report.report_snapshot.blank?

      collector = ReviewNotesCollector.new(report: @report)
      overlay = collector.respond_to?(:overlay) ? collector.overlay : nil
      review_notes = overlay ? overlay["notes"] : collector.call

      html = HtmlBuilder.call(
        snapshot: @report.report_snapshot,
        review_notes: review_notes,
        review_overlay: overlay,
        report_version: @report.version
      )
      upload_artifact!(html)
      @report
    end

    private

    def upload_artifact!(html)
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
        storage_key: storage_key,
        content_type: content_type,
        error_message: html_fallback ? "PDF service unavailable — stored as HTML (not a PDF)." : @report.error_message
      )
    end
  end
end
