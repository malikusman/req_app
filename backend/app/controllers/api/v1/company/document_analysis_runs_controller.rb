# frozen_string_literal: true

module Api
  module V1
    module Company
      class DocumentAnalysisRunsController < BaseController
        def index
          authorize DocumentAnalysisRun, :index?
          runs = policy_scope(DocumentAnalysisRun).recent.limit(20)
          render json: {
            runs: runs.map { |r| run_json(r) },
            awaiting_analysis_count: current_company.documents.portal.awaiting_analysis.count,
            profile_stale: current_company.docs_profile_stale_at.present?,
            active_run: current_company.document_analysis_runs.active.order(created_at: :desc).first&.then { |r| run_json(r) }
          }
        end

        def show
          run = policy_scope(DocumentAnalysisRun).find(params[:id])
          authorize run, :show?
          render json: {
            run: run_json(run),
            events: run.document_analysis_events.order(:created_at).map { |e| event_json(e) }
          }
        end

        def create
          authorize DocumentAnalysisRun, :create?
          run_kind = params[:run_kind].presence || default_run_kind
          run = Documents::StartAnalysisRunService.call(
            company: current_company,
            user: current_company_user,
            run_kind: run_kind,
            document_ids: params[:document_ids]
          )
          render json: { run: run_json(run) }, status: :created
        rescue Documents::StartAnalysisRunService::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def default_run_kind
          if current_company.docs_profile_stale_at.present? &&
             current_company.documents.portal.awaiting_analysis.none?
            "profile_reground"
          elsif current_company.document_analysis_runs.where(status: %w[completed completed_with_errors]).exists?
            "incremental_docs"
          else
            "full"
          end
        end

        def run_json(run)
          {
            id: run.id,
            run_kind: run.run_kind,
            status: run.status,
            phase: run.phase,
            model_tier: run.model_tier,
            document_ids: run.document_ids,
            summary: run.summary,
            counters: run.counters,
            error_message: run.error_message,
            started_at: run.started_at,
            finished_at: run.finished_at,
            created_at: run.created_at
          }
        end

        def event_json(event)
          {
            id: event.id,
            agent_name: event.agent_name,
            event_type: event.event_type,
            phase: event.phase,
            message: event.message,
            payload: event.payload,
            created_at: event.created_at
          }
        end
      end
    end
  end
end
