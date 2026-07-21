# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class CompaniesController < BaseController
        def index
          companies = policy_scope(::Company).includes(:subscription)
          render json: {
            companies: companies.map { |c| company_summary(c) }
          }
        end

        def show
          company = policy_scope(::Company).find(params[:id])
          authorize company, :show?
          latest_report = company.reports.ready.order(version: :desc).first
          my_review = latest_report && ReportReview.find_by(report: latest_report, reviewer_user: current_reviewer_user)

          render json: {
            company: company_summary(company).merge(
              participation: Intelligence::SnapshotBuilder.call(company: company)["participation"],
              latest_report: latest_report ? { id: latest_report.id, version: latest_report.version, status: latest_report.status } : nil,
              my_review_status: my_review&.status,
              co_reviewer_count: company.reviewer_assignments.active.count,
              company_admins: company.company_users.where(role: "company_admin", status: "active").order(:name).map { |u|
                { id: u.id, name: u.name, email: u.email }
              }
            )
          }
        end

        private

        def company_summary(company)
          {
            id: company.id,
            name: company.display_name || company.name,
            report_readiness_score: company.report_readiness_score,
            completed_count: company.completed_count,
            invited_count: company.invited_count
          }
        end
      end
    end
  end
end
