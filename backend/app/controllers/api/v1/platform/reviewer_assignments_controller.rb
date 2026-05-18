# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReviewerAssignmentsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize ReviewerAssignment, :index?
          assignments = company.reviewer_assignments.includes(:reviewer_user, :assigned_by_platform_user).order(assigned_at: :desc)
          render json: {
            assignments: assignments.map { |a| assignment_json(a) },
            active_count: assignments.active.count
          }
        end

        def create
          company = ::Company.find(params[:company_id])
          reviewer = ReviewerUser.active.find(params[:reviewer_user_id])
          authorize ReviewerAssignment.new(company: company), :create?

          assignment = ReviewerAssignments::AssignService.call(
            company: company,
            reviewer_user: reviewer,
            platform_user: current_platform_user,
            request: request
          )

          render json: { assignment: assignment_json(assignment) }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def destroy
          assignment = ReviewerAssignment.find(params[:id])
          authorize assignment, :destroy?
          ReviewerAssignments::RemoveService.call(
            assignment: assignment,
            platform_user: current_platform_user,
            request: request
          )
          head :no_content
        end

        private

        def assignment_json(a)
          {
            id: a.id,
            status: a.status,
            assigned_at: a.assigned_at,
            removed_at: a.removed_at,
            reviewer_user: {
              id: a.reviewer_user_id,
              name: a.reviewer_user.name,
              email: a.reviewer_user.email
            },
            assigned_by: a.assigned_by_platform_user.name
          }
        end
      end
    end
  end
end
