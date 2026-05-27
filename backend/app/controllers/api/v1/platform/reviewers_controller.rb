# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReviewersController < BaseController
        def index
          reviewers = policy_scope(ReviewerUser).order(:name)
          render json: { reviewers: reviewers.map { |r| reviewer_json(r) } }
        end

        def show
          reviewer = ReviewerUser.find(params[:id])
          authorize reviewer, :show?
          render json: { reviewer: reviewer_json(reviewer, detailed: true) }
        end

        def create
          reviewer = ReviewerUser.new(reviewer_params.merge(status: "active", password: params.dig(:reviewer, :password)))
          authorize reviewer, :create?
          reviewer.save!
          render json: { reviewer: reviewer_json(reviewer) }, status: :created
        end

        def update
          reviewer = ReviewerUser.find(params[:id])
          authorize reviewer, :update?
          reviewer.update!(reviewer_params) if params[:reviewer].present?
          if params[:password].present?
            reviewer.update!(password: params[:password])
            reviewer.regenerate_jti!
          end

          if params[:profile].present?
            Reviewers::UpdateProfileService.call(
              reviewer: reviewer,
              params: profile_params,
              experiences: experiences_param,
              publish: publish_param
            )
          end

          if params[:platform_verified].present?
            verified = ActiveModel::Type::Boolean.new.cast(params[:platform_verified])
            reviewer.update!(platform_verified_at: verified ? Time.current : nil)
          end

          render json: { reviewer: reviewer_json(reviewer.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def reviewer_params
          params.require(:reviewer).permit(:email, :name, :status)
        end

        def profile_params
          params.require(:profile).permit(
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
          return nil unless params[:profile]&.key?(:experiences)

          Array(params[:profile][:experiences]).map do |e|
            e.permit(:organization, :title, :start_year, :end_year, :summary, :sort_order).to_h
          end
        end

        def publish_param
          return nil unless params[:profile]&.key?(:publish)

          ActiveModel::Type::Boolean.new.cast(params[:profile][:publish])
        end

        def reviewer_json(reviewer, detailed: false)
          completeness = Reviewers::ProfileCompleteness.call(reviewer)
          json = {
            id: reviewer.id,
            email: reviewer.email,
            name: reviewer.name,
            status: reviewer.status,
            profile_status: reviewer.profile_status,
            profile_completeness_percent: completeness.percent,
            headline: reviewer.headline,
            expertise_tags: reviewer.expertise_tags,
            avatar_url: Reviewers::ProfileSerializer.avatar_path(reviewer, request),
            public_card: Reviewers::ProfileSerializer.public_card(reviewer, request: request)
          }
          if detailed
            json[:profile] = Reviewers::ProfileSerializer.full(reviewer, request: request, include_account: true)
            json[:assignments] = reviewer.reviewer_assignments.active.includes(:company).map do |a|
              { company_id: a.company_id, company_name: a.company.display_name || a.company.name }
            end
          end
          json
        end
      end
    end
  end
end
