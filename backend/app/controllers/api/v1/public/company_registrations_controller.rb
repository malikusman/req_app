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
            admin_phone: params[:admin_phone] || params[:phone],
            website_url: params[:website_url],
            role_title: params[:role_title],
            notes: params[:notes],
            company_profile: profile_params,
            known_systems: known_systems_param
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

        def profile_params
          raw = params[:company_profile]
          return {} if raw.blank?

          permitted = raw.permit(
            :industry, :sub_industry, :size_band, :region, :country,
            :annual_revenue_band,
            business_goals: [],
            org_departments: []
          )
          if raw[:business_goals].is_a?(String)
            permitted[:business_goals] = raw[:business_goals]
          end
          permitted.to_h
        end

        def known_systems_param
          return nil unless params.key?(:known_systems)

          Array(params[:known_systems])
        end
      end
    end
  end
end
