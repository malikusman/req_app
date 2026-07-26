# frozen_string_literal: true

module Api
  module V1
    module Auth
      class PlatformSessionsController < ApplicationController
        def create
          user = PlatformUser.find_by(email: params[:email].to_s.strip.downcase)
          unless user&.authenticate(params[:password].to_s)
            return render json: { error: "Invalid email or password" }, status: :unauthorized
          end

          token = JsonWebToken.encode(
            {
              sub: "platform_user:#{user.id}",
              aud: "platform",
              role: user.role,
              jti: user.jti
            }
          )

          render json: {
            token: token,
            user: platform_user_json(user)
          }
        end

        private

        def platform_user_json(user)
          { id: user.id, email: user.email, name: user.name, role: user.role }
        end
      end
    end
  end
end
