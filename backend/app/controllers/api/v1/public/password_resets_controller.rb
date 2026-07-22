# frozen_string_literal: true

module Api
  module V1
    module Public
      class PasswordResetsController < ApplicationController
        def create
          ::Auth::RequestPasswordReset.call(portal: params[:portal], email: params[:email])
          render json: { ok: true }
        rescue ::Auth::RequestPasswordReset::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def show
          record = ::Auth::PasswordResetToken.verify(params[:token])
          unless record
            return render json: { error: "This link is invalid or has expired" }, status: :not_found
          end

          render json: {
            ok: true,
            portal: portal_for(record),
            email: record.email,
            name: record.try(:name)
          }
        end

        def update
          ::Auth::SetPassword.call(
            token: params[:token],
            password: params[:password],
            password_confirmation: params[:password_confirmation]
          )
          render json: { ok: true }
        rescue ::Auth::SetPassword::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def portal_for(record)
          case record
          when CompanyUser then "company"
          when ReviewerUser then "reviewer"
          when PlatformUser then "platform"
          else "unknown"
          end
        end
      end
    end
  end
end
