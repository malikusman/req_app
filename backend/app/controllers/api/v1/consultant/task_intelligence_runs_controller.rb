# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class TaskIntelligenceRunsController < BaseController
        PAGE_SIZE = 50

        def index
          scope = company_runs
          scope = scope.where("task_intelligence_runs.id < ?", params[:before_id].to_s.to_i) if params[:before_id].present?
          rows = scope.order(id: :desc).limit(PAGE_SIZE + 1).to_a
          page = rows.first(PAGE_SIZE)
          render json: {
            task_intelligence_runs: page.map { |run| run_json(run) },
            next_before_id: rows.size > PAGE_SIZE ? page.last.id : nil
          }
        end

        def show
          run = company_runs.find(params[:id])
          selected, remaining = company_candidates(run).to_a.partition(&:shortlisted?)
          render json: {
            task_intelligence_run: run_json(run).merge(
              shortlist: selected.sort_by(&:rank).map { |candidate| candidate_json(candidate) },
              dispositions: remaining.sort_by { |candidate| [-candidate.score, candidate.id] }
                                     .map { |candidate| candidate_json(candidate) }
            )
          }
        end

        def candidate
          run = company_runs.find(params[:id])
          proposal = company_candidates(run).find(params[:candidate_id])
          render json: { task_candidate: candidate_json(proposal).merge(assessment: proposal.assessment) }
        end

        private

        def company_runs
          company = policy_scope(::Company).find(params[:company_id])
          policy_scope(::TaskIntelligenceRun).where(company: company)
        end

        def company_candidates(run)
          run.candidates.joins(process_cluster_revision: :process_cluster)
             .where(process_clusters: { company_id: run.company_id }).includes(:process_cluster_revision)
        end

        def run_json(run)
          run.as_json(only: %i[id company_id version target_size algorithm_version evaluation_mode created_at])
             .merge(evaluation_limitation: "Semantic AI evaluation was not used. Recommendations are rule-based and require consultant judgment.")
        end

        def candidate_json(candidate)
          revision = candidate.process_cluster_revision
          candidate.as_json(only: %i[id task_intelligence_run_id title disposition disposition_reason rank score priority confidence])
                   .merge(process_cluster_id: revision.process_cluster_id, process_cluster_revision_id: revision.id,
                          process_cluster_revision_number: revision.number)
        end
      end
    end
  end
end
