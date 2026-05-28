# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class FollowupsController < BaseController
        def index
          authorize ReviewerInfoRequest, :index?
          requests = policy_scope(::ReviewerInfoRequest)
            .includes(:employee, :company)
            .where(reviewer_user_id: current_reviewer_user.id)
            .order(updated_at: :desc)

          render json: {
            followups: requests.map { |r| followup_json(r) }
          }
        end

        private

        def followup_json(r)
          {
            id: r.id,
            company_id: r.company_id,
            company_name: r.company.display_name || r.company.name,
            employee_id: r.employee_id,
            employee_name: r.employee.display_name,
            status: r.status,
            body: r.body,
            updated_at: r.updated_at,
            report_id: r.report_id
          }
        end
      end
    end
  end
end
