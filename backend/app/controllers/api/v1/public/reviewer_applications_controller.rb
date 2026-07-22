# frozen_string_literal: true

module Api
  module V1
    module Public
      class ReviewerApplicationsController < ApplicationController
        MAX_PER_WINDOW = 5
        WINDOW = 1.hour

        def create
          return render json: { ok: true }, status: :created if params[:website].present?

          if rate_limited?
            return render json: { error: "Too many requests. Please try again later." },
                          status: :too_many_requests
          end

          reviewer = Registrations::CreateReviewerApplication.call(
            name: params[:name],
            email: params[:email],
            notes: params[:notes],
            expertise_summary: params[:expertise_summary],
            headline: params[:headline]
          )
          render json: { ok: true, application: { id: reviewer.id, status: reviewer.status } },
                 status: :created
        rescue Registrations::CreateReviewerApplication::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::RecordInvalid => e
          render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        private

        def rate_limited?
          key = "reviewer_applications:#{request.remote_ip}"
          count = Rails.cache.increment(key, 1, expires_in: WINDOW)
          count.nil? ? false : count > MAX_PER_WINDOW
        end
      end
    end
  end
end
