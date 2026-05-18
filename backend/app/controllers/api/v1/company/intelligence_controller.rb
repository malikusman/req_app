# frozen_string_literal: true

module Api
  module V1
    module Company
      class IntelligenceController < BaseController
        def snapshot
          authorize current_company, :show?
          company = current_company
          company.update!(intelligence_snapshot: Intelligence::SnapshotBuilder.call(company: company)) if company.intelligence_snapshot.blank?

          render json: {
            snapshot: company.reload.intelligence_snapshot,
            report_readiness_score: company.report_readiness_score,
            report_readiness_breakdown: company.report_readiness_breakdown
          }
        end

        def signals
          authorize current_company, :show?
          signals = company_scope(CompanySignal).order(strength: :desc)
          render json: { signals: signals.map { |s| signal_json(s) } }
        end

        def patterns
          authorize current_company, :show?
          patterns = company_scope(Pattern).order(confidence: :desc)
          render json: { patterns: patterns.map { |p| pattern_json(p) } }
        end

        def timeline
          authorize current_company, :show?
          events = company_scope(InsightTimelineEvent).order(occurred_at: :desc).limit(100)
          render json: { events: events.map { |e| timeline_json(e) } }
        end

        private

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
