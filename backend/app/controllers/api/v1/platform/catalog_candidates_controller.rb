# frozen_string_literal: true

module Api
  module V1
    module Platform
      class CatalogCandidatesController < BaseController
        PER_PAGE = 30

        def index
          candidates = CatalogCandidate.includes(:catalog_source_record).order(created_at: :desc)
          candidates = candidates.where(review_status: params[:review_status]) if params[:review_status].present?
          candidates = candidates.where(analysis_status: params[:analysis_status]) if params[:analysis_status].present?
          candidates = candidates.where(entity_type: params[:entity_type]) if params[:entity_type].present?
          if params[:catalog_source_id].present?
            candidates = candidates.joins(:catalog_source_record)
                                   .where(catalog_source_records: { catalog_source_id: params[:catalog_source_id] })
          end

          page = [params[:page].to_i, 1].max
          per_page = if params[:per_page].present?
                       params[:per_page].to_i.clamp(1, 100)
                     else
                       PER_PAGE
                     end
          total = candidates.count
          records = candidates.offset((page - 1) * per_page).limit(per_page)

          render json: {
            catalog_candidates: records.map { |c| candidate_json(c) },
            pagination: { page: page, per_page: per_page, total: total }
          }
        end

        def show
          candidate = CatalogCandidate.includes(catalog_source_record: :catalog_source).find(params[:id])
          render json: { catalog_candidate: candidate_json(candidate, detail: true) }
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

        def candidate_json(c, detail: false)
          record = c.catalog_source_record
          payload = {
            id: c.id,
            name: c.name,
            vendor: c.vendor,
            entity_type: c.entity_type,
            description: c.description,
            summary: c.summary,
            website_url: c.website_url,
            source_url: c.source_url,
            confidence: c.confidence,
            review_status: c.review_status,
            analysis_status: c.analysis_status,
            analyzed_at: c.analyzed_at,
            published_at: c.published_at,
            industries: c.industries,
            topics: c.topics,
            suggested_catalog_entry_id: c.suggested_catalog_entry_id,
            reviewed_by_platform_user_id: c.reviewed_by_platform_user_id,
            reviewed_at: c.reviewed_at,
            review_note: c.review_note,
            provenance: c.provenance,
            catalog_source_record_id: c.catalog_source_record_id,
            catalog_source_id: record&.catalog_source_id,
            catalog_source_name: c.provenance&.dig("catalog_source_name") || record&.catalog_source&.name,
            created_at: c.created_at,
            updated_at: c.updated_at
          }
          if detail && record
            payload[:source_record] = {
              id: record.id,
              url: record.url,
              title: record.title,
              fetched_at: record.fetched_at,
              parse_status: record.parse_status,
              raw_payload: record.raw_payload,
              catalog_sync_run_id: record.catalog_sync_run_id
            }
          end
          payload
        end
      end
    end
  end
end
