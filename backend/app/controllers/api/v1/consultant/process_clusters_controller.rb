# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ProcessClustersController < BaseController
        PAGE_SIZE = 100

        def index
          scope = company_clusters
          scope = scope.where(active: true) unless params[:include_retired] == "true"
          rows = scope.where("process_clusters.id > ?", params[:after_id].to_s.to_i)
                      .order(:id).limit(PAGE_SIZE + 1).includes(:current_revision).to_a
          page = rows.first(PAGE_SIZE)
          render json: {
            process_clusters: page.map { |cluster| cluster_json(cluster, cluster.current_revision) },
            next_after_id: rows.size > PAGE_SIZE ? page.last.id : nil
          }
        end

        def show
          cluster = company_clusters.find(params[:id])
          revision = if params[:revision].present?
                       cluster.revisions.find_by!(number: params[:revision])
                     else
                       cluster.current_revision || raise(ActiveRecord::RecordNotFound)
                     end
          memberships = revision.memberships.joins(:task_source)
                                .where(task_sources: { company_id: cluster.company_id }).includes(:task_source).order(:id)
          render json: {
            process_cluster: cluster_json(cluster, revision).merge(
              revision_numbers: cluster.revisions.order(:number).pluck(:number),
              relationships: visible_relationships(cluster, revision),
              memberships: memberships.map { |member| membership_json(member) }
            )
          }
        end

        private

        def company_clusters
          company = policy_scope(::Company).find(params[:company_id])
          policy_scope(::ProcessCluster).where(company: company)
        end

        def cluster_json(cluster, revision)
          {
            id: cluster.id, company_id: cluster.company_id, active: cluster.active,
            revision: revision&.as_json(only: %i[number status confidence rationale effort_summary created_at])
          }
        end

        def visible_relationships(cluster, revision)
          ids = revision.relationships.flat_map { |pair| pair.fetch("source_ids") }
          allowed_ids = TaskSource.where(company_id: cluster.company_id, id: ids).pluck(:id).to_set
          revision.relationships.select { |pair| pair.fetch("source_ids").all? { |id| allowed_ids.include?(id) } }
        end

        def membership_json(member)
          source = member.task_source
          source.as_json(only: %i[employee_id conversation_id name source_kind local_task_id version discovery_revision])
                .merge(task_source_id: source.id, effort_observations: member.effort_observations.map do |observation|
                  observation.slice("scope", "effort_type", "annual_hours_min", "annual_hours_max",
                                    "calculation_basis", "calculation_reason").merge(
                    "frequency" => observation.fetch("frequency").except("as_said"),
                    "duration" => observation.fetch("duration").except("as_said")
                  )
                end)
        end
      end
    end
  end
end
