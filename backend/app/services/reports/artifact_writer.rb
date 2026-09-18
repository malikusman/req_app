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

      client = Storage::MinioClient.new
      client.upload(key: storage_key, body: pdf_bytes, content_type: content_type)
      reader_key = upload_reader_html!(client, html_fallback ? nil : storage_key)

      artifact = @report.report_artifacts.find_or_initialize_by(variant: @spec[:variant])
      artifact.update!(
        storage_key: storage_key,
        content_type: content_type,
        reader_storage_key: reader_key,
        page_count: page_count(pdf_bytes),
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

    # The exact HTML behind the shipped PDF, kept so the in-portal reader shows
    # what was approved rather than a live re-render that could drift (or
    # surface a consultant edit made after approval). Skipped when the PDF
    # itself fell back to HTML — that key already holds this content.
    def upload_reader_html!(client, pdf_key)
      return nil if pdf_key.blank?

      key = "#{pdf_key.sub(/\.pdf\z/, "")}.reader.html"
      client.upload(key: key, body: @html, content_type: "text/html")
      key
    rescue StandardError => e
      # A reader that is unavailable is a degraded surface; a report that failed
      # to generate is a broken deliverable. Never trade the second for the first.
      Rails.logger.warn("[Reports::ArtifactWriter] reader HTML not stored: #{e.class}: #{e.message}")
      nil
    end

    def storage_key_for(content_type)
      ext = content_type == "application/pdf" ? "pdf" : "html"
      # The full report keeps its historical path so already-issued share links
      # and stored keys keep resolving; variants get their own suffix.
      name = @spec[:variant] == VariantSpec::FULL ? "report" : @spec[:variant]
      "reports/#{@report.company_id}/v#{@report.version}/#{name}.#{ext}"
    end

    # The PDF is the authority. The HTML section count is only a fallback for
    # the case where there is no PDF to read — Gotenberg down, HTML stored
    # instead — because it counts the pages the document INTENDED to have, and
    # an overflowing section silently adds one.
    def page_count(pdf_bytes)
      PdfPageCounter.call(bytes: pdf_bytes, fallback: html_page_count)
    end

    def html_page_count
      @html.to_s.scan(/<section[^>]*class="[^"]*\bpage\b/).size
    end
  end
end
