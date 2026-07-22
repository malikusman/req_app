# frozen_string_literal: true

module Api
  module V1
    module Public
      class CompanyRegistrationsController < ApplicationController
        MAX_PER_WINDOW = 5
        WINDOW = 1.hour

        def create
          return render json: { ok: true }, status: :created if params[:website].present?

          if rate_limited?
            return render json: { error: "Too many requests. Please try again later." },
                          status: :too_many_requests
          end

          registration = Registrations::CreateCompanyRegistration.call(
            company_name: params[:company_name],
            display_name: params[:display_name],
            admin_name: params[:admin_name],
            admin_email: params[:admin_email],
            role_title: params[:role_title],
            notes: params[:notes]
          )
          render json: { ok: true, registration: { id: registration.id, status: registration.status } },
                 status: :created
        rescue Registrations::CreateCompanyRegistration::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::RecordInvalid => e
          render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        private

        def rate_limited?
          key = "company_registrations:#{request.remote_ip}"
          count = Rails.cache.increment(key, 1, expires_in: WINDOW)
          count.nil? ? false : count > MAX_PER_WINDOW
        end
      end
    end
  end
end
