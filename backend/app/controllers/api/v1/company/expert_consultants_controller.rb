# frozen_string_literal: true

module Api
  module V1
    module Company
      class ExpertConsultantsController < BaseController
        def index
          consultants = current_company.consultant_assignments.active
            .includes(consultant_user: :consultant_experiences)
            .map(&:consultant_user)
            .select(&:published_profile?)

          render json: {
            expert_consultants: consultants.map { |r| Consultants::ProfileSerializer.public_card(r, request: request) }
          }
        end
      end
    end
  end
end
