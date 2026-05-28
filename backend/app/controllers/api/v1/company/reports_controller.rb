# frozen_string_literal: true

module Api
  module V1
    module Company
      class ReportsController < BaseController
        def index
          reports = policy_scope(Report).order(version: :desc)
          render json: { reports: reports.map { |r| report_json(r) } }
        end

        def show
          report = policy_scope(Report).find(params[:id])
          authorize report, :show?
          return render json: { error: "Report not available" }, status: :forbidden if report.visibility != "shared_with_company"

          payload = { report: report_json(report, detailed: true) }
          if report.status == "ready"
            payload[:expert_reviewers] = expert_reviewers_for_company
          end
          render json: payload
        end

        def create
          authorize Report, :create?
          if current_company.report_readiness_score < 100 && !current_company.merged_settings["allow_early_report"]
            return render json: { error: "Report readiness must reach 100% before generating" }, status: :unprocessable_entity
          end

          previous = current_company.reports.ready.order(version: :desc).first
          has_reviewers = current_company.reviewer_assignments.active.exists?
          report = current_company.reports.create!(
            version: (current_company.reports.maximum(:version) || 0) + 1,
            status: "queued",
            visibility: "internal_only",
            review_workflow_status: has_reviewers ? "not_required" : "reviews_complete",
            triggered_by_type: "CompanyUser",
            triggered_by_id: current_company_user.id,
            previous_report: previous
          )

          GenerateReportJob.perform_later(report.id)
          render json: { report: report_json(report) }, status: :accepted
        end

        def download
          report = policy_scope(Report).find(params[:id])
          authorize report, :download?
          return render json: { error: "Report not ready" }, status: :not_found unless report.status == "ready"
          return render json: { error: "Report not available" }, status: :forbidden if report.visibility != "shared_with_company"

          data = Storage::MinioClient.new.download(report.storage_key)
          send_data data,
                    filename: "discovery-report-v#{report.version}.#{report.content_type == 'application/pdf' ? 'pdf' : 'html'}",
                    type: report.content_type,
                    disposition: "attachment"
        end

        def share
          report = policy_scope(Report).find(params[:id])
          authorize report, :share?
          days = params[:days].to_i
          result = Reports::ShareLinkService.create!(report: report, days: days.positive? ? days : 30)
          render json: result
        end

        private

        def expert_reviewers_for_company
          current_company.reviewer_assignments.active
            .includes(:reviewer_user)
            .map(&:reviewer_user)
            .select(&:published_profile?)
            .map { |r| Reviewers::ProfileSerializer.public_card(r, request: request) }
        end

        def report_json(report, detailed: false)
          access_count = report.report_share_accesses.count
          last_access = report.report_share_accesses.maximum(:accessed_at)

          json = {
            id: report.id,
            version: report.version,
            status: report.status,
            visibility: report.visibility,
            review_workflow_status: report.review_workflow_status,
            generated_at: report.generated_at,
            share_token_expires_at: report.share_token_expires_at,
            share_active: report.share_active?,
            access_count: access_count,
            last_accessed_at: last_access,
            delta_summary: report.report_snapshot.dig("delta_from_previous", "summary"),
            error_message: report.error_message
          }

          json[:report_snapshot] = report.report_snapshot if detailed
          json[:share_url] = "#{ENV.fetch('API_PUBLIC_HOST', 'http://localhost:3000')}/api/v1/public/reports/#{report.share_token}" if report.share_token.present?
          json
        end
      end
    end
  end
end
