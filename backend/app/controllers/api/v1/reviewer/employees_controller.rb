# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class EmployeesController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          employees = policy_scope(::Employee).where(company_id: company.id)
          render json: { employees: employees.map { |e| employee_json(e) } }
        end

        def show
          employee = policy_scope(::Employee).find(params[:id])
          authorize employee, :show?
          render json: { employee: employee_json(employee) }
        end

        private

        def employee_json(employee)
          {
            id: employee.id,
            phone_e164: employee.phone_e164,
            display_name: employee.display_name,
            department: employee.department,
            participation_status: employee.participation_status,
            preferred_language: employee.preferred_language,
            started_at: employee.started_at,
            completed_at: employee.completed_at,
            last_active_at: employee.last_active_at
          }
        end
      end
    end
  end
end
