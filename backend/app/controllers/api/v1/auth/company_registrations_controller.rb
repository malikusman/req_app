# frozen_string_literal: true

module Api
  module V1
    module Auth
      class CompanyRegistrationsController < ApplicationController
        def create
          return throttle_response if throttled?("company_signup", params[:email])

          ActiveRecord::Base.transaction do
            company_name = params.require(:company_name)
            company = ::Company.create!(
              name: company_name,
              display_name: company_name,
              slug: params[:company_slug].presence || company_name.parameterize
            )
            user = company.company_users.create!(
              email: params.require(:email),
              name: resolved_name,
              password: params.require(:password),
              role: "company_admin",
              status: "active"
            )

            token = JsonWebToken.encode(
              {
                sub: "company_user:#{user.id}",
                aud: "company",
                company_id: company.id,
                role: user.role,
                jti: user.jti
              }
            )

            render json: {
              token: token,
              user: {
                id: user.id,
                email: user.email,
                name: user.name,
                role: user.role,
                onboarding_completed_at: user.onboarding_completed_at
              },
              company: {
                id: company.id,
                name: company.name,
                display_name: company.display_name,
                locale: company.locale,
                portal_onboarding_completed_at: company.portal_onboarding_completed_at
              }
            }, status: :created
          end
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
        rescue ActiveRecord::RecordNotUnique
          render json: { error: "Company already exists" }, status: :unprocessable_entity
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
