# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReportsController < BaseController
        def index
          company = ::Company.find(params[:company_id])
          reports = policy_scope(Report).where(company_id: company.id).order(version: :desc)
          render json: {
            reports: reports.map { |r| report_json(r, company: company) },
            has_active_reviewers: company.reviewer_assignments.active.exists?
          }
        end

        def create
          company = ::Company.find(params[:company_id])
          authorize Report, :create?

          if company.report_readiness_score < 100 && !company.merged_settings["allow_early_report"]
            return render json: { error: "Report readiness must reach 100% before generating" }, status: :unprocessable_entity
          end

          previous = company.reports.ready.order(version: :desc).first
          report = company.reports.create!(
            version: (company.reports.maximum(:version) || 0) + 1,
            status: "queued",
            visibility: "internal_only",
            review_workflow_status: company.reviewer_assignments.active.exists? ? "not_required" : "reviews_complete",
            triggered_by_type: "PlatformUser",
            triggered_by_id: current_platform_user.id,
            previous_report: previous
          )

          GenerateReportJob.perform_later(report.id)
          render json: { report: report_json(report, company: company) }, status: :accepted
        end

        def approve
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize report, :approve?

          Reports::ReleaseService.call(
            report: report,
            platform_user: current_platform_user,
            request: request
          )

          render json: { report: report_json(report.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def regenerate
          source_report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize source_report, :approve?

          report = Reports::RegenerateFromReviewService.call(
            source_report: source_report,
            requested_by: current_platform_user,
            note: params[:note]
          )

          render json: { report: report_json(report.reload) }, status: :accepted
        end

        private

        def report_json(report, company: report.company)
          active_reviewer_ids = company.reviewer_assignments.active.pluck(:reviewer_user_id)
          reviews = report.report_reviews.where(reviewer_user_id: active_reviewer_ids)

          {
            id: report.id,
            version: report.version,
            status: report.status,
            visibility: report.visibility,
            review_workflow_status: report.review_workflow_status,
            regeneration_source_report_id: report.regeneration_source_report_id,
            reviews_completed_at: report.reviews_completed_at,
            generated_at: report.generated_at,
            company_id: report.company_id,
            reviewer_progress: reviews.map { |rv| reviewer_progress_json(rv) }
          }
        end

        def reviewer_progress_json(rv)
          {
            reviewer_user_id: rv.reviewer_user_id,
            reviewer_name: rv.reviewer_user.name,
            status: rv.status,
            sign_off_status: rv.sign_off_status,
            ready_at: rv.ready_at,
            ready_note: rv.ready_note,
            submitted_at: rv.submitted_at
          }
        end
      end
    end
  end
end
