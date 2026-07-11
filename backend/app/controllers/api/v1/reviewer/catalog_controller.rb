# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class CatalogController < BaseController
        def index
          company = find_assigned_company!
          matches = CompanyCatalogMatch.where(company_id: company.id)
            .includes(:solution_catalog_entry)
            .order(score: :desc, matched_at: :desc)

          render json: {
            matches: matches.map { |m| match_json(m) }
          }
        end

        def endorse
          company = find_assigned_company!
          match = CompanyCatalogMatch.where(company_id: company.id).find(params[:id])

          endorsement = CatalogEndorsement.create!(
            company: company,
            report_id: params[:report_id],
            reviewer_user: current_reviewer_user,
            solution_catalog_entry: match.solution_catalog_entry,
            disposition: params.require(:disposition),
            rationale: params[:rationale],
            source_url: params[:source_url],
            publishable: params[:publishable] != false
          )

          render json: { endorsement: endorsement_json(endorsement) }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def find_assigned_company!
          company = ::Company.find(params[:company_id])
          unless assigned_company_ids.include?(company.id)
            raise ActiveRecord::RecordNotFound
          end

          company
        end

        def match_json(m)
          entry = m.solution_catalog_entry
          {
            id: m.id,
            score: m.score,
            why_it_fits: m.why_it_fits,
            evidence_used: m.evidence_used,
            assumptions: m.assumptions,
            risks: m.risks,
            estimated_effort: m.estimated_effort,
            validate_next: m.validate_next,
            matched_at: m.matched_at,
            solution_catalog_entry: entry && {
              id: entry.id,
              name: entry.name,
              vendor: entry.vendor,
              category: entry.category,
              entity_type: entry.try(:entity_type),
              website_url: entry.website_url,
              description: entry.description
            }
          }
        end

        def endorsement_json(e)
          {
            id: e.id,
            company_id: e.company_id,
            report_id: e.report_id,
            reviewer_user_id: e.reviewer_user_id,
            solution_catalog_entry_id: e.solution_catalog_entry_id,
            disposition: e.disposition,
            rationale: e.rationale,
            source_url: e.source_url,
            publishable: e.publishable,
            created_at: e.created_at
          }
        end
      end
    end
  end
end
