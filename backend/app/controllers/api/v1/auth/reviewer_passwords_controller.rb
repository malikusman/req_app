# frozen_string_literal: true

module Api
  module V1
    module Auth
      class ReviewerPasswordsController < ApplicationController
        def forgot
          return throttle_response if throttled?("reviewer_forgot_password", params[:email])

          user = ReviewerUser.find_by(email: params[:email].to_s.downcase.strip, status: "active")
          if user
            token = user.issue_password_reset_token!
            reset_url = "#{ENV.fetch('APP_HOST', 'http://localhost:5173')}/reviewer/reset-password?token=#{token}"
            SendPasswordResetEmailJob.perform_later("reviewer", user.id, reset_url)
          end

          render json: { ok: true }
        end

        def reset
          token = params.require(:token)
          user = ReviewerUser.find_by(password_reset_token_digest: Digest::SHA256.hexdigest(token))
          return render json: { error: "Invalid or expired token" }, status: :unprocessable_entity unless user&.password_reset_token_valid?(token)

          user.update!(password: params.require(:password))
          user.regenerate_jti!
          user.clear_password_reset_token!
          render json: { ok: true }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end

        private

        def throttled?(scope, key)
          k = "throttle:#{scope}:#{request.remote_ip}:#{key.to_s.downcase.strip}"
          count = Rails.cache.fetch(k, expires_in: 10.minutes) { 0 }.to_i + 1
          Rails.cache.write(k, count, expires_in: 10.minutes)
          count > 10
        end

        def throttle_response
          render json: { ok: true }
        end
      end
    end
  end
end
