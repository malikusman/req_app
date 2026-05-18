# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ProfileController < BaseController
        def update
          authorize current_reviewer_user, :update?
          current_reviewer_user.update!(profile_params)
          if params[:password].present?
            current_reviewer_user.update!(password: params[:password])
            current_reviewer_user.regenerate_jti!
          end
          render json: { ok: true, user: { id: current_reviewer_user.id, email: current_reviewer_user.email, name: current_reviewer_user.name } }
        end

        private

        def profile_params
          params.permit(:name, :email)
        end
      end
    end
  end
end
