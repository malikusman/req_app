# frozen_string_literal: true

module Api
  module V1
    module Platform
      class IntelligenceController < BaseController
        before_action :load_company

        def snapshot
          authorize @company, :show?
          @company.update!(intelligence_snapshot: Intelligence::SnapshotBuilder.call(company: @company)) if @company.intelligence_snapshot.blank?

          render json: {
            snapshot: @company.reload.intelligence_snapshot,
            report_readiness_score: @company.report_readiness_score,
            report_readiness_breakdown: @company.report_readiness_breakdown
          }
        end

        def signals
          authorize @company, :show?
          signals = policy_scope(::CompanySignal).where(company_id: @company.id).order(strength: :desc)
          render json: { signals: signals.map { |s| signal_json(s) } }
        end

        def patterns
          authorize @company, :show?
          patterns = policy_scope(::Pattern).where(company_id: @company.id).order(confidence: :desc)
          render json: { patterns: patterns.map { |p| pattern_json(p) } }
        end

        def recommendations
          authorize @company, :show?
          recs = policy_scope(::Recommendation).where(company_id: @company.id).published.order(priority: :desc, created_at: :desc)
          render json: { recommendations: recs.map { |r| recommendation_json(r) } }
        end

        def timeline
          authorize @company, :show?
          events = policy_scope(::InsightTimelineEvent).where(company_id: @company.id).order(occurred_at: :desc).limit(100)
          render json: { events: events.map { |e| timeline_json(e) } }
        end

        private

        def load_company
          @company = policy_scope(::Company).find(params[:company_id])
        end

        def signal_json(signal)
          {
            id: signal.id,
            label: signal.label,
            signal_type: signal.signal_type,
            strength: signal.strength,
            departments: signal.departments,
            evidence_count: signal.evidence_count,
            status: signal.status,
            first_seen_at: signal.first_seen_at,
            last_updated_at: signal.last_updated_at
          }
        end

        def pattern_json(pattern)
          {
            id: pattern.id,
            title: pattern.title,
            description: pattern.description,
            confidence: pattern.confidence,
            departments: pattern.departments,
            status: pattern.status,
            linked_signal_ids: pattern.linked_signal_ids,
            first_seen_at: pattern.first_seen_at,
            last_updated_at: pattern.last_updated_at
          }
        end

        def recommendation_json(rec)
          {
            id: rec.id,
            title: rec.title,
            description: rec.description,
            priority: rec.priority,
            status: rec.status,
            catalog_matches: rec.catalog_matches
          }
        end

        def timeline_json(event)
          {
            id: event.id,
            event_type: event.event_type,
            title: event.title,
            summary: event.summary,
            occurred_at: event.occurred_at,
            target_type: event.target_type,
            target_id: event.target_id
          }
        end
      end
    end
  end
end
