# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReportsController < BaseController
        def index
          company = ::Company.find(params[:company_id])
          reports = company.reports.order(version: :desc)
          render json: { reports: reports.map { |r| report_json(r) } }
        end

        def approve
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          report.update!(
            visibility: "shared_with_company",
            reviewed_by_platform_user: current_platform_user,
            reviewed_at: Time.current
          )

          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "report_approved",
            target: report,
            request: request
          )

          render json: { report: report_json(report) }
        end

        private

        def report_json(report)
          {
            id: report.id,
            version: report.version,
            status: report.status,
            visibility: report.visibility,
            generated_at: report.generated_at,
            company_id: report.company_id
          }
        end
      end
    end
  end
end
