# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ReviewSyncController < BaseController
        def show
          company = policy_scope(::Company).find(params[:company_id])
          report = company.reports.ready.find(params[:report_id])

          since = params[:since].present? ? Time.zone.parse(params[:since]) : 1.hour.ago

          reviews = report.report_reviews.includes(:reviewer_user, :report_review_comments, :report_review_section_states)
          comments = ReportReviewComment.joins(:report_review)
            .where(report_reviews: { report_id: report.id })
            .where("report_review_comments.updated_at >= ?", since)

          render json: {
            synced_at: Time.current.iso8601,
            reviews: reviews.map { |r| { reviewer_user_id: r.reviewer_user_id, status: r.status, submitted_at: r.submitted_at } },
            comments: comments.map { |c|
              {
                id: c.id,
                section_key: c.section_key,
                body: c.body,
                reviewer_user_id: c.reviewer_user_id,
                updated_at: c.updated_at
              }
            },
            section_states: reviews.flat_map { |r|
              r.report_review_section_states.map { |s|
                { reviewer_user_id: r.reviewer_user_id, section_key: s.section_key, status: s.status }
              }
            }
          }
        end
      end
    end
  end
end
