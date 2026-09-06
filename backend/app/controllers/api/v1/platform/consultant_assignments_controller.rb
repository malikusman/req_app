# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ConsultantAssignmentsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize ConsultantAssignment, :index?
          assignments = company.consultant_assignments
            .includes(:assigned_by_platform_user, consultant_user: :consultant_experiences)
            .order(assigned_at: :desc)
          render json: {
            assignments: assignments.map { |a| assignment_json(a) },
            active_count: assignments.active.count
          }
        end

        def create
          company = ::Company.find(params[:company_id])
          consultant = ConsultantUser.active.find(params[:consultant_user_id])
          authorize ConsultantAssignment.new(company: company), :create?

          assignment = ConsultantAssignments::AssignService.call(
            company: company,
            consultant_user: consultant,
            platform_user: current_platform_user,
            request: request
          )

          render json: { assignment: assignment_json(assignment) }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def destroy
          assignment = ConsultantAssignment.find(params[:id])
          authorize assignment, :destroy?
          ConsultantAssignments::RemoveService.call(
            assignment: assignment,
            platform_user: current_platform_user,
            request: request
          )
          head :no_content
        end

        private

        def consultant_user_json(consultant)
          {
            id: consultant.id,
            name: consultant.name,
            email: consultant.email,
            profile_status: consultant.profile_status,
            profile_completeness_percent: Consultants::ProfileCompleteness.call(consultant).percent,
            public_card: Consultants::ProfileSerializer.public_card(consultant, request: request)
          }
        end

        def assignment_json(a)
          {
            id: a.id,
            status: a.status,
            assigned_at: a.assigned_at,
            removed_at: a.removed_at,
            consultant_user: consultant_user_json(a.consultant_user),
            assigned_by: a.assigned_by_platform_user.name
          }
        end
      end
    end
  end
end
