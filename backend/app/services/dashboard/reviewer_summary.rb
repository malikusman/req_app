# frozen_string_literal: true

module Dashboard
  class ReviewerSummary
    OPEN_FOLLOWUP_STATUSES = %w[awaiting_reply sent].freeze
    SUBMITTED_REVIEW_STATUSES = %w[approved rejected].freeze

    def self.call(reviewer_user:, companies:)
      new(reviewer_user: reviewer_user, companies: companies).call
    end

    def initialize(reviewer_user:, companies:)
      @reviewer_user = reviewer_user
      @companies = companies
    end

    def call
      company_rows = @companies.map { |company| company_row(company) }
      followups = followup_rows
      completeness = Reviewers::ProfileCompleteness.call(@reviewer_user)

      {
        profile: {
          profile_completeness_percent: completeness.percent,
          profile_status: @reviewer_user.profile_status
        },
        stats: stats_for(company_rows, followups),
        attention_items: attention_items_for(company_rows),
        recent_followups: followups.first(3),
        companies: company_rows,
        unread_count: Notification.where(
          recipient_type: "ReviewerUser",
          recipient_id: @reviewer_user.id,
          read_at: nil
        ).count
      }
    end

    private

    def company_row(company)
      latest_report = company.reports.where(status: "ready").order(version: :desc).first
      my_review = latest_report && ReportReview.find_by(report: latest_report, reviewer_user: @reviewer_user)
      participation = Intelligence::SnapshotBuilder.call(company: company)["participation"]

      {
        id: company.id,
        name: company.display_name || company.name,
        report_readiness_score: company.report_readiness_score,
        completed_count: company.completed_count,
        invited_count: company.invited_count,
        participation: participation,
        latest_report: latest_report ? {
          id: latest_report.id,
          version: latest_report.version,
          status: latest_report.status
        } : nil,
        my_review_status: my_review&.status,
        co_reviewer_count: company.reviewer_assignments.active.where.not(reviewer_user_id: @reviewer_user.id).count,
        review_pending: review_pending?(latest_report, my_review)
      }
    end

    def followup_rows
      ReviewerInfoRequest
        .where(reviewer_user_id: @reviewer_user.id)
        .includes(:company, :employee)
        .order(updated_at: :desc)
        .map do |request|
          {
            id: request.id,
            company_id: request.company_id,
            company_name: request.company.display_name || request.company.name,
            employee_id: request.employee_id,
            employee_name: request.employee.display_name,
            status: request.status,
            last_message: request.body,
            updated_at: request.updated_at
          }
        end
    end

    def stats_for(company_rows, followups)
      avg_readiness =
        if company_rows.empty?
          0
        else
          (company_rows.sum { |row| row[:report_readiness_score].to_f } / company_rows.size).round
        end

      {
        assigned_companies: company_rows.size,
        avg_readiness: avg_readiness,
        total_completed: company_rows.sum { |row| row[:completed_count] },
        total_invited: company_rows.sum { |row| row[:invited_count] },
        pending_reviews: company_rows.count { |row| row[:review_pending] },
        open_followups: followups.count { |row| OPEN_FOLLOWUP_STATUSES.include?(row[:status]) }
      }
    end

    def attention_items_for(company_rows)
      company_rows.filter_map do |row|
        next unless row[:review_pending]

        {
          company_id: row[:id],
          company_name: row[:name],
          report_id: row[:latest_report][:id],
          report_version: row[:latest_report][:version],
          review_status: row[:my_review_status]
        }
      end
    end

    def review_pending?(latest_report, my_review)
      return false unless latest_report&.status == "ready"

      status = my_review&.status
      status.blank? || !SUBMITTED_REVIEW_STATUSES.include?(status)
    end
  end
end
