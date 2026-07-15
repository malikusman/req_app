# frozen_string_literal: true

module Api
  module V1
    module Platform
      class CatalogCandidatesController < BaseController
        def index
          candidates = CatalogCandidate.order(created_at: :desc)
          candidates = candidates.where(review_status: params[:review_status]) if params[:review_status].present?
          render json: { catalog_candidates: candidates.limit(200).map { |c| candidate_json(c) } }
        end

        def approve
          candidate = CatalogCandidate.find(params[:id])
          entry = Catalog::PromoteCandidateService.call(
            candidate: candidate,
            platform_user: current_platform_user,
            review_note: params[:review_note],
            attributes: params[:attributes].presence || {}
          )
          render json: {
            catalog_candidate: candidate_json(candidate.reload),
            solution_catalog_entry: { id: entry.id, name: entry.name, slug: entry.slug }
          }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject
          candidate = CatalogCandidate.find(params[:id])
          unless candidate.review_status == "pending"
            return render json: { error: "Candidate already reviewed" }, status: :unprocessable_entity
          end

          candidate.update!(
            review_status: "rejected",
            reviewed_by_platform_user: current_platform_user,
            reviewed_at: Time.current,
            review_note: params[:review_note]
          )
          render json: { catalog_candidate: candidate_json(candidate) }
        end

        def merge
          candidate = CatalogCandidate.find(params[:id])
          unless candidate.review_status == "pending"
            return render json: { error: "Candidate already reviewed" }, status: :unprocessable_entity
          end

          entry = SolutionCatalogEntry.find(params.require(:solution_catalog_entry_id))
          candidate.update!(
            review_status: "merged",
            suggested_catalog_entry: entry,
            reviewed_by_platform_user: current_platform_user,
            reviewed_at: Time.current,
            review_note: params[:review_note]
          )
          render json: {
            catalog_candidate: candidate_json(candidate),
            solution_catalog_entry: { id: entry.id, name: entry.name, slug: entry.slug }
          }
        end

        private

        def candidate_json(c)
          {
            id: c.id,
            name: c.name,
            vendor: c.vendor,
            entity_type: c.entity_type,
            description: c.description,
            website_url: c.website_url,
            confidence: c.confidence,
            review_status: c.review_status,
            suggested_catalog_entry_id: c.suggested_catalog_entry_id,
            reviewed_by_platform_user_id: c.reviewed_by_platform_user_id,
            reviewed_at: c.reviewed_at,
            review_note: c.review_note,
            provenance: c.provenance,
            catalog_source_record_id: c.catalog_source_record_id,
            created_at: c.created_at,
            updated_at: c.updated_at
          }
        end
      end
    end
  end
end
