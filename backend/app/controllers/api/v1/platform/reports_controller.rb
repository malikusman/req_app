# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReportsController < BaseController
        include Api::V1::ReportDownload

        def index
          company = ::Company.find(params[:company_id])
          reports = policy_scope(Report).where(company_id: company.id).order(version: :desc)
          render json: { reports: reports.map { |r| report_json(r, company: company) } }
        end

        def download
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize report, :download?
          send_report_download(report, disposition: download_disposition)
        end

        # WYSIWYG preview with pending reviewer edits applied — so the approver
        # sees exactly what the client will get before approving the regenerate.
        def preview
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize report, :download?
          send_report_preview(report)
        end

        def approve
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize report, :approve?

          if report.review_workflow_status.in?(%w[awaiting_reviewers in_review])
            return render json: { error: "Reviewer reviews not yet complete" }, status: :unprocessable_entity
          end

          if report.company.reviewer_assignments.active.exists? &&
             report.review_workflow_status != "reviews_complete" &&
             !report.company.merged_settings["skip_platform_review"]
            return render json: { error: "All reviewer submissions required before approval" }, status: :unprocessable_entity
          end

          Reports::RegenerateWithReviewService.call(report: report) if report.report_reviews.exists?

          report.update!(
            visibility: "shared_with_company",
            review_workflow_status: "platform_approved",
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

        def report_json(report, company: report.company)
          active_reviewer_ids = company.reviewer_assignments.active.pluck(:reviewer_user_id)
          reviews = report.report_reviews.where(reviewer_user_id: active_reviewer_ids)
            .includes(:reviewer_user, :report_review_comments)

          {
            id: report.id,
            version: report.version,
            status: report.status,
            visibility: report.visibility,
            review_workflow_status: report.review_workflow_status,
            reviews_completed_at: report.reviews_completed_at,
            generated_at: report.generated_at,
            company_id: report.company_id,
            reviewer_progress: reviews.map do |rv|
              {
                reviewer_user_id: rv.reviewer_user_id,
                reviewer_name: rv.reviewer_user.name,
                status: rv.status,
                submitted_at: rv.submitted_at
              }
            end,
            reviewer_feedback: reviewer_feedback_json(reviews)
          }
        end

        def reviewer_feedback_json(reviews)
          reviews.map do |review|
            {
              reviewer_name: review.reviewer_user.name,
              status: review.status,
              submitted_at: review.submitted_at,
              overall_note: review.overall_note,
              comments: review.report_review_comments.order(:created_at).map do |comment|
                {
                  id: comment.id,
                  section_key: comment.section_key,
                  body: comment.body
                }
              end
            }
          end
        end
      end
    end
  end
end
