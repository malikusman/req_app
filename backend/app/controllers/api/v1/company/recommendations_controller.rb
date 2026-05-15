# frozen_string_literal: true

module Api
  module V1
    module Company
      class RecommendationsController < BaseController
        def index
          recs = company_scope(Recommendation).published.order(priority: :desc, created_at: :desc)
          render json: { recommendations: recs.map { |r| recommendation_json(r) } }
        end

        def update_feedback
          rec = company_scope(Recommendation).find(params[:id])
          rec.update!(
            company_feedback: params[:feedback],
            company_feedback_note: params[:note],
            company_feedback_at: Time.current,
            company_feedback_by: current_company_user
          )

          RecommendationFeedback.create!(
            recommendation: rec,
            company_user: current_company_user,
            feedback: params[:feedback],
            note: params[:note]
          )

          render json: { recommendation: recommendation_json(rec) }
        end

        private

        def recommendation_json(rec)
          {
            id: rec.id,
            title: rec.title,
            description: rec.description,
            implementation_outline: rec.implementation_outline,
            priority: rec.priority,
            status: rec.status,
            catalog_matches: rec.catalog_matches,
            company_feedback: rec.company_feedback,
            company_feedback_note: rec.company_feedback_note,
            company_feedback_at: rec.company_feedback_at,
            created_at: rec.created_at
          }
        end
      end
    end
  end
end
