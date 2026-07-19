# frozen_string_literal: true

module Api
  module V1
    module Public
      class DemoRequestsController < ApplicationController
        MAX_PER_WINDOW = 5
        WINDOW = 1.hour

        def create
          # Honeypot: bots fill the hidden "website" field. Pretend success.
          return render json: { ok: true }, status: :created if params[:website].present?

          if rate_limited?
            return render json: { error: "Too many requests. Please try again later." },
                          status: :too_many_requests
          end

          demo_request = DemoRequest.new(demo_request_params)
          if demo_request.save
            DemoRequestMailer.notify(demo_request).deliver_later
            render json: { ok: true }, status: :created
          else
            render json: { errors: demo_request.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def demo_request_params
          params.permit(:name, :email, :company_name, :role, :notes)
        end

        def rate_limited?
          key = "demo_requests:#{request.remote_ip}"
          count = Rails.cache.increment(key, 1, expires_in: WINDOW)
          count.nil? ? false : count > MAX_PER_WINDOW
        end
      end
    end
  end
end
