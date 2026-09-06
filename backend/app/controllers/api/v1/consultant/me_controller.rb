# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class MeController < BaseController
        def show
          consultant = current_consultant_user
          completeness = Consultants::ProfileCompleteness.call(consultant)
          render json: {
            user: {
              id: consultant.id,
              email: consultant.email,
              name: consultant.name
            },
            profile: Consultants::ProfileSerializer.full(consultant, request: request),
            profile_completeness_percent: completeness.percent,
            assignments: policy_scope(::ConsultantAssignment).active.includes(:company).map do |a|
              {
                company_id: a.company_id,
                company_name: a.company.display_name || a.company.name,
                assigned_at: a.assigned_at
              }
            end
          }
        end
      end
    end
  end
end
