# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class FollowupsController < BaseController
        def index
          requests = policy_scope(::ConsultantInfoRequest)
            .includes(:company, :employee)
            .where(consultant_user_id: current_consultant_user.id)
            .order(updated_at: :desc)

          render json: {
            followups: requests.map { |r| followup_json(r) }
          }
        end

        private

        def followup_json(request)
          {
            id: request.id,
            company_id: request.company_id,
            company_name: request.company.display_name || request.company.name,
            employee_id: request.employee_id,
            employee_name: request.employee.display_name,
            status: request.status,
            last_message: request.body,
            updated_at: request.updated_at,
            sent_at: request.sent_at
          }
        end
      end
    end
  end
end
