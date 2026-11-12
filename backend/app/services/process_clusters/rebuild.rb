# frozen_string_literal: true

require "digest"

module ProcessClusters
  class Rebuild
    def self.call(company:)
      new(company).call
    end

    def initialize(company)
      @company = company
    end

    def call
      @company.with_lock do
        sources = latest_sources
        evidence = evidence_for(sources)
        observations = evidence.transform_values { |item| EffortReconciliation.observations(item) }
        matcher = Relationship.new(evidence)
        pairs = sources.combination(2).each_with_object({}) do |(left, right), found|
          relationship = matcher.compare(left, right)
          found[[left.id, right.id].sort] = relationship if relationship
        end
        ReconcileClarifications.new(company: @company, evidence: evidence, observations: observations).call(pairs)

        clusters = partition(sources, pairs).map do |members|
          save_group(members, pairs, observations)
        end
        retire_absent_clusters(clusters)
        clusters
      end
    end

    private

    # Load one TaskSource version per conversation-local identity. The first ID
    # gives the group a stable anchor and ordering even as source versions change.
    def latest_sources
      keys = "conversation_id, source_kind, local_task_id"
      TaskSource.where(company_id: @company.id)
                .select("DISTINCT ON (#{keys}) task_sources.*, MIN(id) OVER (PARTITION BY #{keys}) AS first_source_id")
                .order(Arel.sql("#{keys}, version DESC")).reject(&:retired?).sort_by(&:first_source_id)
    end

    def evidence_for(sources)
      ids = sources.flat_map { |source| source.evidence_references.pluck("message_id") }.compact
      evidence_conversations = TaskSource.evidence_messages.where(id: ids).pluck(:id, :conversation_id).to_h
      sources.index_by(&:id).transform_values { |source| SourceEvidence.new(source, evidence_conversations) }
    end

    # Synthesis groups the same work again, with P10 and the consultant's
    # decisions kept across runs (Synthesis::ClusterAssembler) (docs/CONSOLIDATION_ENGINES.md §3).
    def partition(sources, pairs)
      groups = []
      sources.each do |source|
        # A third activity must match every member. A chain of tentative or
        # partially compatible pairs cannot silently pull a new activity in.
        group = groups.find do |members|
          members.all? { |member| Relationship::GROUPABLE.include?(pairs[[member.id, source.id].sort]&.fetch("kind")) }
        end
        group ? group << source : groups << [source]
      end
      groups
    end

    def save_group(members, pairs, observations)
      ids = members.map(&:id)
      relationships = pairs.values.select { |pair| pair["source_ids"].intersect?(ids) }
      within = relationships.select { |pair| (pair["source_ids"] - ids).empty? }
      confidence, rationale = grouping_basis(members, within)
      effort = EffortReconciliation.summarize(members, observations, within)
      if (relationships - within).any? { |relationship| Relationship::OVERLAP_KINDS.include?(relationship["kind"]) }
        effort["cross_cluster_overlap_unresolved"] = true
      end
      cluster = ProcessCluster.find_or_create_by!(company: @company, anchor_key: members.first.first_source_id.to_s)
      append_revision(
        cluster, observations.slice(*ids), status: "active", confidence: confidence, rationale: rationale,
        relationships: relationships, effort_summary: effort
      )
      cluster
    end

    def grouping_basis(members, within)
      return ["low", "A single observation is retained until there is sufficient evidence to group it."] if members.one?
      if within.all? { |pair| pair["kind"] == "same_work" }
        return ["high", "All member pairs agree on recorded steps, trigger and output."]
      end

      ["medium", "Each pair agrees on the work, supports a shared variant, or has an evidenced output-to-trigger handoff."]
    end

    def retire_absent_clusters(clusters)
      ProcessCluster.where(company: @company, active: true).where.not(id: clusters.map(&:id)).find_each do |cluster|
        append_revision(cluster, {}, status: "retired", confidence: "low", rationale: "No current group uses this anchor.",
                        relationships: [], effort_summary: EffortReconciliation.summarize([], {}, []))
      end
    end

    def append_revision(cluster, observations, **attributes)
      latest = cluster.revisions.order(number: :desc).first
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([attributes, observations]))
      return if latest&.fingerprint == fingerprint

      revision = cluster.revisions.create!(**attributes, fingerprint: fingerprint, number: (latest&.number || 0) + 1)
      observations.each do |source_id, effort|
        revision.memberships.create!(task_source_id: source_id, effort_observations: effort)
      end
      cluster.update!(active: attributes.fetch(:status) == "active")
    end
  end
end
