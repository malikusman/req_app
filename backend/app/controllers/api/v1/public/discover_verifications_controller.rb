# frozen_string_literal: true

module Api
  module V1
    module Public
      class DiscoverVerificationsController < ApplicationController
        def create
          result = EmployeeWebSessions::VerifyService.call(
            token: params[:token],
            access_code: params[:access_code],
            ip_address: request.remote_ip
          )
          render json: result
        rescue EmployeeWebSessions::VerifyService::RateLimited
          render json: { error: "Too many attempts. Please try again later." }, status: :too_many_requests
        rescue EmployeeWebSessions::VerifyService::InvalidSession, EmployeeWebSessions::VerifyService::InvalidCode
          render json: { error: "Invalid link or access code" }, status: :unauthorized
        end
      end
    end
  end
end
