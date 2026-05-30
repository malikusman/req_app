# frozen_string_literal: true

module Reports
  class GenerateReportService
    GROUNDING_THRESHOLD = 0.6

    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
      @company = report.company
      @client = Langgraph::Client.new
    end

    def call
      @report.update!(status: "generating")

      previous = @report.previous_report
      delta = DeltaCalculator.call(company: @company, previous_report: previous)
      snapshot = SnapshotBuilder.call(company: @company, delta: delta)
      merge_regeneration_feedback!(snapshot)
      merge_context_bundle!(snapshot)
      merge_ai_narratives!(snapshot)
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

      if @company.reviewer_assignments.active.exists?
        ReportReviews::BootstrapService.call(report: @report)
      else
        @report.update!(review_workflow_status: "reviews_complete")
      end

      NotificationService.notify_report_ready(company: @company, report: @report)
      @report
    rescue StandardError => e
      @report.update!(status: "failed", error_message: e.message)
      raise
    end

    private

    def merge_context_bundle!(snapshot)
      bundle = Knowledge::ContextBundleService.call(company: @company)
      snapshot["context_bundle"] = bundle
    end

    def merge_ai_narratives!(snapshot)
      return unless Companies::AgentFeatures.enabled?(@company, :ai_report_narrative)

      thread_id = @client.create_thread!
      result = @client.generate_report!(
        thread_id: thread_id,
        company_id: @company.id,
        snapshot: snapshot
      )
      narratives = result["narratives"] || {}
      return if narratives.blank?

      snapshot["ai_narratives"] = narratives
      grounding = narratives["grounding_score"].to_f

      if grounding < GROUNDING_THRESHOLD
        AgentInterrupt.create!(
          thread_id: thread_id,
          company: @company,
          kind: "report_section",
          status: "pending",
          payload: {
            "grounding_score" => grounding,
            "narratives" => narratives,
            "report_id" => @report.id
          }
        )
      end
    rescue Langgraph::UnavailableError
      snapshot["ai_narratives"] = { "error" => "agent_unavailable" }
    end

    def merge_regeneration_feedback!(snapshot)
      source = @report.regeneration_source_report
      return unless source

      reviews = source.report_reviews.includes(:reviewer_user, :report_review_comments, :report_review_section_states)
      snapshot["regeneration"] = {
        "source_report_id" => source.id,
        "source_report_version" => source.version,
        "requested_note" => @report.regeneration_note,
        "reviewer_feedback" => reviews.map { |review|
          {
            "reviewer_name" => review.reviewer_user.name,
            "status" => review.status,
            "sign_off_status" => review.sign_off_status,
            "overall_note" => review.overall_note,
            "ready_note" => review.ready_note,
            "section_states" => review.report_review_section_states.map { |s| { "section_key" => s.section_key, "status" => s.status } },
            "comments" => review.report_review_comments.order(:created_at).map { |c|
              { "section_key" => c.section_key, "body" => c.body }
            }
          }
        }
      }
    end
  end
end
