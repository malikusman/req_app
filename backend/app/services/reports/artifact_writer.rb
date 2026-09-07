# frozen_string_literal: true

module Reports
  # Renders one variant and stores it. Both GenerateReportService and
  # RegenerateWithReviewService used to carry their own copy of this
  # render → PDF → MinIO → update block, which is how they drifted (the
  # regenerate path cleared a stale error_message; the generate path did not).
  # Now there is one.
  class ArtifactWriter
    def self.call(report:, variant:, html:)
      new(report: report, variant: variant, html: html).call
    end

    def initialize(report:, variant:, html:)
      @report = report
      @spec = VariantSpec.for(variant)
      @html = html
    end

    def call
      pdf_bytes = PdfGenerator.call(html: @html, paper: @spec[:paper])
      html_fallback = pdf_bytes == @html
      content_type = html_fallback ? "text/html" : "application/pdf"
      storage_key = storage_key_for(content_type)

      Storage::MinioClient.new.upload(key: storage_key, body: pdf_bytes, content_type: content_type)

      artifact = @report.report_artifacts.find_or_initialize_by(variant: @spec[:variant])
      artifact.update!(
        storage_key: storage_key,
        content_type: content_type,
        page_count: page_count,
        generated_at: Time.current,
        error_message: html_fallback ? FALLBACK_MESSAGE : nil
      )

      # The full report stays on `reports.storage_key` too. Every existing
      # download path, share link and approval check reads that column, and
      # breaking them to prove a point about normalization is not worth it.
      if @spec[:variant] == VariantSpec::FULL
        @report.update!(
          storage_key: storage_key,
          content_type: content_type,
          error_message: html_fallback ? FALLBACK_MESSAGE : nil
        )
      end

      artifact
    end

    FALLBACK_MESSAGE = "PDF service unavailable — stored as HTML (not a PDF)."

    private

    def storage_key_for(content_type)
      ext = content_type == "application/pdf" ? "pdf" : "html"
      # The full report keeps its historical path so already-issued share links
      # and stored keys keep resolving; variants get their own suffix.
      name = @spec[:variant] == VariantSpec::FULL ? "report" : @spec[:variant]
      "reports/#{@report.company_id}/v#{@report.version}/#{name}.#{ext}"
    end

    # Counted from the rendered HTML rather than the PDF, so the portal can say
    # "4 pp" on the button — which is the whole reason the brief gets clicked.
    def page_count
      @html.to_s.scan(/<section[^>]*class="[^"]*\bpage\b/).size
    end
  end
end
