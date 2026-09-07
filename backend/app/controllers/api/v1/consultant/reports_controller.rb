# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ReportsController < BaseController
        include Api::V1::ReportDownload

        def index
          company = policy_scope(::Company).find(params[:company_id])
          reports = policy_scope(::Report).where(company_id: company.id).order(version: :desc)
          render json: { reports: reports.map { |r| report_json(r) } }
        end

        def show
          report = policy_scope(::Report).find(params[:id])
          authorize report, :show?
          render json: { report: report_detail_json(report) }
        end

        def download
          report = policy_scope(::Report).find(params[:id])
          authorize report, :download?
          disposition = params[:inline].present? ? "inline" : "attachment"
          send_report_download(report, disposition: disposition)
        end

        # WYSIWYG live preview: renders the deliverable with the consultant's pending
        # section edits + publishable findings applied (never stored).
        def preview
          report = policy_scope(::Report).find(params[:id])
          authorize report, :download?
          return head :unprocessable_entity if report.report_snapshot.blank?

          # The consultant must be able to SEE the brief before submitting. Four
          # pages is where a weak governing thought does maximum damage — there
          # is no surrounding detail to soften it.
          variant = normalize_variant(nil)
          return if performed?

          html = Reports::RegenerateWithReviewService.render_html(report: report, variant: variant)
          send_data html, type: "text/html", disposition: "inline"
        end

        # New evidence keeps arriving after a report is reviewed — more interviews
        # complete, more documents land, signals strengthen. The consultant is the
        # one who knows whether that changes the advice, so they can mint the next
        # version themselves rather than waiting on the company to click Generate.
        #
        # A new VERSION, not a silent re-render: the delta section then states what
        # changed, and their section overrides carry forward so re-review starts
        # from their existing work rather than from scratch.
        def refresh
          report = policy_scope(::Report).find(params[:id])
          authorize report, :download?

          result = Reports::ConsultantRefreshService.call(
            report: report, consultant_user: current_consultant_user
          )
          render json: { report: report_json(result[:report]), stale: result[:stale] }, status: :accepted
        rescue Reports::ConsultantRefreshService::NotStale => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def report_json(report)
          review = ReportReview.find_by(report: report, consultant_user: current_consultant_user)
          {
            id: report.id,
            version: report.version,
            status: report.status,
            review_workflow_status: report.review_workflow_status,
            my_review_status: review&.status,
            my_review_submitted: review&.submitted?
          }
        end

        def report_detail_json(report)
          report_json(report).merge(
            report_snapshot: report.report_snapshot,
            generated_at: report.generated_at,
            storage_key: report.storage_key.present?
          )
        end
      end
    end
  end
end
