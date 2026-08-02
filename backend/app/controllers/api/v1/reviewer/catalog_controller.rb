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
            matches: matches.map { |m| match_json(m) },
            last_matched_at: matches.maximum(:matched_at),
            note: "These are promoted catalog tools matched to this company — not the live web scrape queue.",
            endorsements: CatalogEndorsement
              .where(company_id: company.id)
              .includes(:solution_catalog_entry, :reviewer_user)
              .order(created_at: :desc)
              .limit(50)
              .map { |e| endorsement_json(e) }
          }
        end

        # Catalog products (first-party + third-party) not yet matched to this
        # company — the pool a reviewer can add from.
        def available
          company = find_assigned_company!
          matched_ids = CompanyCatalogMatch.where(company_id: company.id).pluck(:solution_catalog_entry_id)
          entries = SolutionCatalogEntry.where(active: true).where.not(id: matched_ids)
          entries = entries.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
          entries = entries.order(first_party: :desc, name: :asc).limit(100)
          render json: { solutions: entries.map { |e| solution_json(e) } }
        end

        # Reviewer attaches a catalog product to this company's recommended list.
        def add_product
          company = find_assigned_company!
          entry = SolutionCatalogEntry.find(params.require(:solution_catalog_entry_id))
          match = CompanyCatalogMatch.find_or_initialize_by(company: company, solution_catalog_entry: entry)
          match.assign_attributes(
            score: match.score.to_f.positive? ? match.score : 0.75,
            why_it_fits: params[:why_it_fits].presence || "Added by reviewer as a relevant fit for this company.",
            added_by_reviewer: current_reviewer_user,
            matched_at: match.matched_at || Time.current
          )
          match.save!
          render json: { match: match_json(match) }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
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
            added_by_reviewer_id: m.added_by_reviewer_id,
            added_by_reviewer_name: m.added_by_reviewer&.name,
            solution_catalog_entry: entry && solution_json(entry)
          }
        end

        def solution_json(entry)
          {
            id: entry.id,
            name: entry.name,
            vendor: entry.vendor,
            category: entry.category,
            entity_type: entry.try(:entity_type),
            first_party: entry.try(:first_party),
            website_url: entry.website_url,
            description: entry.description
          }
        end

        def endorsement_json(e)
          entry = e.solution_catalog_entry
          {
            id: e.id,
            company_id: e.company_id,
            report_id: e.report_id,
            reviewer_user_id: e.reviewer_user_id,
            reviewer_name: e.reviewer_user&.name,
            solution_catalog_entry_id: e.solution_catalog_entry_id,
            solution_name: entry&.name,
            solution_vendor: entry&.vendor,
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
