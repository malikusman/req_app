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

        def update_questionnaire
          answers = (current_reviewer_user.questionnaire_answers || {}).merge(questionnaire_answers_param)
          step = params[:questionnaire_step].presence&.to_i
          step = step.clamp(1, 9) if step

          attrs = { questionnaire_answers: answers }
          attrs[:questionnaire_step] = step if step
          current_reviewer_user.update!(attrs)

          Reviewers::QuestionnaireSync.call(reviewer: current_reviewer_user, answers: answers)

          progress = Reviewers::QuestionnaireProgress.call(answers, reviewer: current_reviewer_user.reload)
          if progress[:completion_percent] >= 100 && current_reviewer_user.questionnaire_completed_at.blank?
            current_reviewer_user.update!(questionnaire_completed_at: Time.current)
          end

          render json: profile_response(current_reviewer_user.reload).merge(
            questionnaire_answers: current_reviewer_user.questionnaire_answers,
            questionnaire_step: current_reviewer_user.questionnaire_step,
            questionnaire_completed_at: current_reviewer_user.questionnaire_completed_at,
            completion_percent: progress[:completion_percent],
            section_status: progress[:section_status]
          )
        end

        def avatar
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          Reviewers::AvatarUploadService.call(reviewer: current_reviewer_user, file: file)
          render json: profile_response(current_reviewer_user.reload)
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def cv
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          Reviewers::CvUploadService.call(reviewer: current_reviewer_user, file: file)
          render json: profile_response(current_reviewer_user.reload)
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def show_cv
          return head :not_found if current_reviewer_user.cv_storage_key.blank?

          data = Storage::MinioClient.new.download(current_reviewer_user.cv_storage_key)
          send_data data, type: "application/pdf", disposition: "inline", filename: "cv.pdf"
        rescue Aws::S3::Errors::NoSuchKey
          head :not_found
        end

        private

        def profile_response(reviewer)
          progress = Reviewers::QuestionnaireProgress.call(reviewer.questionnaire_answers, reviewer: reviewer)
          {
            ok: true,
            user: {
              id: reviewer.id,
              email: reviewer.email,
              name: reviewer.name
            },
            profile: Reviewers::ProfileSerializer.full(reviewer, request: request, include_account: false),
            questionnaire_answers: reviewer.questionnaire_answers || {},
            questionnaire_step: reviewer.questionnaire_step,
            questionnaire_completed_at: reviewer.questionnaire_completed_at,
            completion_percent: progress[:completion_percent],
            section_status: progress[:section_status]
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

        def questionnaire_answers_param
          raw = params[:questionnaire_answers] || params[:answers] || {}
          return {} unless raw.respond_to?(:to_unsafe_h) || raw.is_a?(Hash)

          hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
          hash.stringify_keys.slice(*Reviewers::QuestionnaireProgress::FIELD_IDS).tap do |cleaned|
            if cleaned["experiences"].is_a?(Array)
              cleaned["experiences"] = cleaned["experiences"].map do |row|
                next row unless row.respond_to?(:to_unsafe_h) || row.is_a?(Hash)

                r = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
                r.stringify_keys.slice("organization", "title", "start_year", "end_year", "summary", "sort_order")
              end
            end
          end
        end
      end
    end
  end
end
