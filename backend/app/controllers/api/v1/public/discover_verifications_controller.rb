# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverVerificationsController < ApplicationController
        def create
          result = EmployeeWebSessions::VerifyService.call(
            token: params[:token],
            ip_address: request.remote_ip
          )
          render json: result
        rescue EmployeeWebSessions::VerifyService::RateLimited
          render json: { error: "Too many attempts. Please try again later." }, status: :too_many_requests
        rescue EmployeeWebSessions::VerifyService::LimitReached => e
          render json: { error: e.message }, status: :payment_required
        rescue EmployeeWebSessions::VerifyService::AlreadyStarted
          render json: { error: "This link was already used. Open the interview from the same browser session, or ask your admin for a new invite." }, status: :conflict
        rescue EmployeeWebSessions::VerifyService::InvalidSession
          render json: { error: "Invalid or expired link" }, status: :unauthorized
        end
      end
    end
  end
end
