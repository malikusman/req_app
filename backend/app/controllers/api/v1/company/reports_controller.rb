# frozen_string_literal: true

module Api
  module V1
    module Company
      class ReportsController < BaseController
        before_action :require_company_admin!, except: %i[index show download]

        def index
          reports = company_scope(Report).order(version: :desc)
          render json: { reports: reports.map { |r| report_json(r) } }
        end

        def show
          report = company_scope(Report).find(params[:id])
          render json: { report: report_json(report, detailed: true) }
        end

        def create
          if current_company.report_readiness_score < 100 && !current_company.merged_settings["allow_early_report"]
            return render json: { error: "Report readiness must reach 100% before generating" }, status: :unprocessable_entity
          end

          previous = current_company.reports.ready.order(version: :desc).first
          report = current_company.reports.create!(
            version: (current_company.reports.maximum(:version) || 0) + 1,
            status: "queued",
            visibility: "shared_with_company",
            triggered_by_type: "CompanyUser",
            triggered_by_id: current_company_user.id,
            previous_report: previous
          )

          GenerateReportJob.perform_later(report.id)
          render json: { report: report_json(report) }, status: :accepted
        end

        def download
          report = company_scope(Report).find(params[:id])
          return render json: { error: "Report not ready" }, status: :not_found unless report.status == "ready"

          data = Storage::MinioClient.new.download(report.storage_key)
          send_data data,
                    filename: "discovery-report-v#{report.version}.#{report.content_type == 'application/pdf' ? 'pdf' : 'html'}",
                    type: report.content_type,
                    disposition: "attachment"
        end

        def share
          report = company_scope(Report).find(params[:id])
          days = params[:days].to_i
          result = Reports::ShareLinkService.create!(report: report, days: days.positive? ? days : 30)
          render json: result
        end

        private

        def require_company_admin!
          render json: { error: "Forbidden" }, status: :forbidden unless current_company_user.company_admin?
        end

        def report_json(report, detailed: false)
          access_count = report.report_share_accesses.count
          last_access = report.report_share_accesses.maximum(:accessed_at)

          json = {
            id: report.id,
            version: report.version,
            status: report.status,
            visibility: report.visibility,
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
