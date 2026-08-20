# frozen_string_literal: true

module Reports
  # Re-renders and uploads the report artifact, merging submitted reviewer notes into the PDF appendix.
  class RegenerateWithReviewService
    def self.call(report:)
      new(report: report).call
    end

    # Live render of the deliverable WITH pending reviewer edits + findings,
    # without storing anything — powers the WYSIWYG preview for reviewer/platform.
    def self.render_html(report:)
      new(report: report).render_html
    end

    def initialize(report:)
      @report = report
      @company = report.company
    end

    def call
      raise ArgumentError, "Report not ready" unless @report.status == "ready"
      raise ArgumentError, "Report snapshot missing" if @report.report_snapshot.blank?

      html = render_html
      upload_artifact!(html)
      @report
    end

    def render_html
      raise ArgumentError, "Report snapshot missing" if @report.report_snapshot.blank?

      collector = ReviewNotesCollector.new(report: @report)
      overlay = collector.respond_to?(:overlay) ? collector.overlay : nil
      review_notes = overlay ? overlay["notes"] : collector.call

      # Apply reviewer editorial overrides (hide / edit / add sections) to a copy
      # of the stored snapshot — the persisted snapshot is untouched.
      snapshot = SectionOverridesApplier.call(snapshot: @report.report_snapshot, report: @report)

      HtmlBuilder.call(
        snapshot: snapshot,
        review_notes: review_notes,
        review_overlay: overlay,
        report_version: @report.version
      )
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
        # Clear any stale failure message on a successful (real PDF) regenerate —
        # otherwise a since-fixed report keeps telling the company "PDF unavailable".
        error_message: html_fallback ? "PDF service unavailable — stored as HTML (not a PDF)." : nil
      )
    end
  end
end
