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

        # Cross-tenant worklist: every report sitting on the approval gate, across
        # all companies. The operator's core queue.
        def pending
          render json: { reports: Dashboard::PlatformSummary.reports_awaiting }
        end

        def download
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize report, :download?
          disposition = params[:inline].present? ? "inline" : "attachment"
          send_report_download(report, disposition: disposition)
        end

        # WYSIWYG preview with pending reviewer edits applied — so the approver
        # sees exactly what the client will get before approving the regenerate.
        def preview
          report = Report.joins(:company).find_by!(id: params[:id], company_id: params[:company_id])
          authorize report, :download?
          return head :unprocessable_entity if report.report_snapshot.blank?

          html = Reports::RegenerateWithReviewService.render_html(report: report)
          send_data html, type: "text/html", disposition: "inline"
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

          # A reviewer flagging sections as "needs clarification" must block approval —
          # resolve (regenerate with the requested changes, or have the reviewer
          # re-mark them) before the report can ship to the company.
          if report.report_reviews.where(status: "needs_info").exists?
            return render json: {
              error: "A reviewer flagged sections needing clarification. Regenerate with the requested changes, or have the reviewer resolve them, before approving."
            }, status: :unprocessable_entity
          end

          begin
            Reports::RegenerateWithReviewService.call(report: report) if report.report_reviews.exists?
          rescue StandardError => e
            return render json: {
              error: "Couldn't regenerate the report for approval (PDF service may be down). Try again shortly. (#{e.message})"
            }, status: :service_unavailable
          end

          # Never ship a broken deliverable — a report that fell back to HTML
          # (Gotenberg down) is not a real PDF and must not be approved/shared.
          if report.reload.content_type != "application/pdf"
            return render json: {
              error: "The report PDF could not be generated (the PDF service may be unavailable). Approval is blocked until a real PDF is produced."
            }, status: :service_unavailable
          end

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

          # The report is now genuinely downloadable — this is the moment to tell
          # the company (previously silent).
          NotificationService.notify_report_ready(company: report.company, report: report)

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
