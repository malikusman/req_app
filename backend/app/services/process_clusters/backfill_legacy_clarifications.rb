# frozen_string_literal: true

module ProcessClusters
  # Creates requests for explicitly selected, still-current legacy comparisons.
  # The saved relationship, cluster, and review snapshots are read only.
  class BackfillLegacyClarifications
    VERIFICATION = [
      "Compare the trigger, inputs, outputs, and handoff for both reported workflows.",
      "Confirm which steps and workload are shared and which are performed separately."
    ].freeze

    def self.call(company:, source_pairs:)
      pairs = source_pairs.map(&:sort).uniq
      company.with_lock do
        revisions = ProcessCluster.where(company: company, active: true).includes(:current_revision)
                                  .filter_map(&:current_revision)
        memberships = ProcessClusterMembership.where(process_cluster_revision: revisions, task_source_id: pairs.flatten)
        observations = memberships.pluck(:task_source_id, :effort_observations).to_h
        sources = current_sources(company, observations.keys)
        relationships = revisions.flat_map(&:relationships).group_by { |pair| pair.fetch("source_ids").sort }
        legacy = pairs.filter_map do |ids|
          saved = relationships[ids]
          next unless ids.size == 2 && ids.uniq == ids && ids.all? { |id| sources.key?(id) } && saved.present?
          next unless saved.all? { |pair| pair["kind"] == "uncertain" && pair["classification"].nil? }

          saved.first.merge("missing_evidence" => saved.first["missing_evidence"].presence || VERIFICATION)
        end

        message_ids = sources.values.flat_map { |source| source.evidence_references.pluck("message_id") }.compact
        conversations = TaskSource.evidence_messages.where(id: message_ids).pluck(:id, :conversation_id).to_h
        evidence = sources.transform_values { |source| SourceEvidence.new(source, conversations) }
        ReconcileClarifications.new(company: company, evidence: evidence, observations: observations).backfill_missing(legacy)
      end
    end

    def self.current_sources(company, ids)
      identity = <<~SQL.squish
        versions.company_id = task_sources.company_id
        AND versions.conversation_id = task_sources.conversation_id
        AND versions.source_kind = task_sources.source_kind
        AND versions.local_task_id = task_sources.local_task_id
      SQL
      TaskSource.where(company: company, id: ids, retired: false)
                .select("task_sources.*, (SELECT MIN(versions.id) FROM task_sources versions WHERE #{identity}) AS first_source_id")
                .where("NOT EXISTS (SELECT 1 FROM task_sources versions WHERE #{identity} AND versions.version > task_sources.version)")
                .index_by(&:id)
    end
    private_class_method :current_sources
  end
end
