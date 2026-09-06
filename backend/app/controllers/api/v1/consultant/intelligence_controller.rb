# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class IntelligenceController < BaseController
        before_action :load_company

        def signals
          signals = policy_scope(::CompanySignal).where(company_id: @company.id).order(strength: :desc)
          render json: { signals: signals.map { |s| signal_json(s) } }
        end

        def patterns
          patterns = policy_scope(::Pattern).where(company_id: @company.id).order(confidence: :desc)
          render json: { patterns: patterns.map { |p| pattern_json(p) } }
        end

        def recommendations
          recs = policy_scope(::Recommendation).where(company_id: @company.id)
          render json: { recommendations: recs.map { |r| recommendation_json(r) } }
        end

        private

        def load_company
          @company = policy_scope(::Company).find(params[:company_id])
        end

        def signal_json(s)
          {
            id: s.id,
            label: s.label,
            strength: s.strength,
            signal_type: s.signal_type,
            departments: s.departments,
            evidence_count: s.evidence_count,
            multimodal_evidence: s.metadata.fetch("multimodal_evidence", []),
            source_excerpts: s.metadata.fetch("source_excerpts", [])
          }
        end

        def pattern_json(p)
          { id: p.id, title: p.title, description: p.description, confidence: p.confidence, departments: p.departments }
        end

        def recommendation_json(r)
          { id: r.id, title: r.title, description: r.description, priority: r.priority, catalog_matches: r.catalog_matches }
        end
      end
    end
  end
end
