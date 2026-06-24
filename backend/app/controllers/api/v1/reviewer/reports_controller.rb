# frozen_string_literal: true

module Api
  module V1
    module Reviewer
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

        private

        def report_json(report)
          review = ReportReview.find_by(report: report, reviewer_user: current_reviewer_user)
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
