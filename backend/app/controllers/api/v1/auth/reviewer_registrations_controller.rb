# frozen_string_literal: true

module Api
  module V1
    module Auth
      class ReviewerRegistrationsController < ApplicationController
        def create
          return throttle_response if throttled?("reviewer_signup", params[:email])

          user = ReviewerUser.create!(
            email: params.require(:email),
            name: resolved_name,
            password: params.require(:password),
            status: "active"
          )

          token = JsonWebToken.encode(
            {
              sub: "reviewer_user:#{user.id}",
              aud: "reviewer",
              role: "reviewer",
              jti: user.jti
            }
          )

          render json: {
            token: token,
            user: {
              id: user.id,
              email: user.email,
              name: user.name
            }
          }, status: :created
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
          render json: { error: "Too many requests, try later" }, status: :too_many_requests
        end

        def resolved_name
          first = params[:first_name].to_s.strip
          last = params[:last_name].to_s.strip
          full = [first, last].reject(&:blank?).join(" ")
          full.presence || params.require(:name)
        end
      end
    end
  end
end
