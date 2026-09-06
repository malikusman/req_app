# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ConsultantsController < BaseController
        def index
          consultants = policy_scope(ConsultantUser).includes(:consultant_experiences).order(:name)
          render json: { consultants: consultants.map { |r| consultant_json(r) } }
        end

        def show
          consultant = ConsultantUser.find(params[:id])
          authorize consultant, :show?
          render json: { consultant: consultant_json(consultant, detailed: true) }
        end

        def cv
          consultant = ConsultantUser.find(params[:id])
          authorize consultant, :show?
          return head :not_found if consultant.cv_storage_key.blank?

          data = Storage::MinioClient.new.download(consultant.cv_storage_key)
          send_data data, type: "application/pdf", disposition: "inline", filename: "#{consultant.name.parameterize}-cv.pdf"
        rescue Aws::S3::Errors::NoSuchKey
          head :not_found
        end

        def create
          consultant = ConsultantUser.new(consultant_params.merge(status: "active", password: params.dig(:consultant, :password)))
          authorize consultant, :create?
          consultant.save!
          render json: { consultant: consultant_json(consultant) }, status: :created
        end

        def update
          consultant = ConsultantUser.find(params[:id])
          authorize consultant, :update?
          consultant.update!(consultant_params) if params[:consultant].present?
          if params[:password].present?
            consultant.update!(password: params[:password])
            consultant.regenerate_jti!
          end

          if params[:profile].present?
            Consultants::UpdateProfileService.call(
              consultant: consultant,
              params: profile_params,
              experiences: experiences_param,
              publish: publish_param
            )
          end

          if params[:platform_verified].present?
            verified = ActiveModel::Type::Boolean.new.cast(params[:platform_verified])
            consultant.update!(platform_verified_at: verified ? Time.current : nil)
          end

          render json: { consultant: consultant_json(consultant.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def consultant_params
          params.require(:consultant).permit(:email, :name, :status)
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

        def consultant_json(consultant, detailed: false)
          completeness = Consultants::ProfileCompleteness.call(consultant)
          json = {
            id: consultant.id,
            email: consultant.email,
            name: consultant.name,
            status: consultant.status,
            profile_status: consultant.profile_status,
            profile_completeness_percent: completeness.percent,
            headline: consultant.headline,
            expertise_tags: consultant.expertise_tags,
            avatar_url: Consultants::ProfileSerializer.avatar_path(consultant, request),
            public_card: Consultants::ProfileSerializer.public_card(consultant, request: request)
          }
          if detailed
            profile = Consultants::ProfileSerializer.full(consultant, request: request, include_account: true)
            if consultant.cv_storage_key.present?
              profile[:cv_url] = "/api/v1/platform/consultants/#{consultant.id}/cv"
            end
            json[:profile] = profile
            json[:has_cv] = consultant.cv_storage_key.present?
            json[:assignments] = consultant.consultant_assignments.active.includes(:company).map do |a|
              { company_id: a.company_id, company_name: a.company.display_name || a.company.name }
            end
          end
          json
        end
      end
    end
  end
end
