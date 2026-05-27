# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ProfileController < BaseController
        def show
          render json: profile_response(current_reviewer_user)
        end

        def update
          if params[:password].present?
            current_reviewer_user.update!(password: params[:password])
            current_reviewer_user.regenerate_jti!
          end

          current_reviewer_user.update!(account_params) if account_params.present?

          Reviewers::UpdateProfileService.call(
            reviewer: current_reviewer_user,
            params: profile_scalar_params,
            experiences: experiences_param,
            publish: publish_param
          )

          render json: profile_response(current_reviewer_user.reload)
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def avatar
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          Reviewers::AvatarUploadService.call(reviewer: current_reviewer_user, file: file)
          render json: profile_response(current_reviewer_user.reload)
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def profile_response(reviewer)
          {
            ok: true,
            user: {
              id: reviewer.id,
              email: reviewer.email,
              name: reviewer.name
            },
            profile: Reviewers::ProfileSerializer.full(reviewer, request: request, include_account: false)
          }
        end

        def account_params
          params.permit(:name, :email).to_h.compact_blank.presence
        end

        def profile_scalar_params
          params.permit(
            :headline,
            :bio,
            :linkedin_url,
            :website_url,
            :location,
            :timezone,
            :years_experience,
            languages: [],
            expertise_tags: [],
            industries: [],
            credentials: %i[label issuer year]
          ).to_h
        end

        def experiences_param
          return nil unless params.key?(:experiences)

          Array(params[:experiences]).map do |e|
            e.permit(:organization, :title, :start_year, :end_year, :summary, :sort_order).to_h
          end
        end

        def publish_param
          return nil unless params.key?(:publish)

          ActiveModel::Type::Boolean.new.cast(params[:publish])
        end
      end
    end
  end
end
