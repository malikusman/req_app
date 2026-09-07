# frozen_string_literal: true

module Reports
  # Re-renders and uploads the report artifact, merging submitted consultant notes into the PDF appendix.
  class RegenerateWithReviewService
    def self.call(report:)
      new(report: report).call
    end

    # Live render of the deliverable WITH pending consultant edits + findings,
    # without storing anything — powers the WYSIWYG preview for consultant/platform.
    def self.render_html(report:, variant: VariantSpec::FULL)
      new(report: report).render_html(variant: variant)
    end

    def initialize(report:)
      @report = report
      @company = report.company
    end

    def call
      raise ArgumentError, "Report not ready" unless @report.status == "ready"
      raise ArgumentError, "Report snapshot missing" if @report.report_snapshot.blank?

      VariantSpec::VARIANTS.each do |variant|
        ArtifactWriter.call(report: @report, variant: variant, html: render_html(variant: variant))
      end
      @report
    end

    def render_html(variant: VariantSpec::FULL)
      raise ArgumentError, "Report snapshot missing" if @report.report_snapshot.blank?

      collector = ReviewNotesCollector.new(report: @report)
      overlay = collector.respond_to?(:overlay) ? collector.overlay : nil
      review_notes = overlay ? overlay["notes"] : collector.call

      # Apply consultant editorial overrides (hide / edit / add sections) to a copy
      # of the stored snapshot — the persisted snapshot is untouched.
      snapshot = SectionOverridesApplier.call(snapshot: @report.report_snapshot, report: @report)

      HtmlBuilder.call(
        snapshot: snapshot,
        review_notes: review_notes,
        review_overlay: overlay,
        report_version: @report.version,
        variant: variant
      )
    end
  end
end
