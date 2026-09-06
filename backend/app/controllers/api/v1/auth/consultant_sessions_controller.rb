# frozen_string_literal: true

module Api
  module V1
    module Auth
      class ConsultantSessionsController < ApplicationController
        def create
          user = ConsultantUser.active.find_by(email: params[:email].to_s.strip.downcase)
          unless user&.authenticate(params[:password].to_s)
            return render json: { error: "Invalid email or password" }, status: :unauthorized
          end

          token = JsonWebToken.encode(
            {
              sub: "consultant_user:#{user.id}",
              aud: "consultant",
              role: "consultant",
              jti: user.jti
            }
          )

          render json: {
            token: token,
            user: consultant_user_json(user)
          }
        end

        private

        def consultant_user_json(user)
          {
            id: user.id,
            email: user.email,
            name: user.name
          }
        end
      end
    end
  end
end
