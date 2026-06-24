# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverSessionsController < ApplicationController
        def show
          session = EmployeeWebSessions::ResolveService.call(token: params[:token])
          return head :not_found unless session

          employee = session.employee
          company = employee.company

          render json: {
            company_name: company.display_name || company.name,
            employee_name: employee.display_name,
            expires_at: session.expires_at,
            requires_verification: !session.verified?
          }
        end
      end
    end
  end
end
