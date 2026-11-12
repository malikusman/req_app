# frozen_string_literal: true

module Synthesis
  # One pass of consolidation and synthesis over an engagement (Doc 10 §5,
  # stages A–H), in the background. Incremental where it can be (Doc 10 §19):
  #
  #   - only pairs not yet judged, or whose wording or figures changed since,
  #     go to P10;
  #   - clusters are reassembled from the current verdicts, keeping their keys,
  #     and get a new version only when they changed;
  #   - a consultant's cluster is never reshaped — a new item that belongs in
  #     it is offered as a suggestion;
  #   - P11 re-reads the whole engagement (basic re-clustering, Doc 10 §28), and
  #     only the outputs that changed get new versions.
  #
  # A failure leaves the previous run and everything it produced as they were.
  class Run
    def self.call(run, client: Synthesis.client_for(run.company)) = new(run, client).call

    # What synthesis reads, as one fingerprint: a change to any of it makes the
    # latest synthesis stale.
    def self.input_digest(engagement)
      company = engagement.company
      findings = company.findings.live.order(:id).pluck(:id, :updated_at, :draft_digest, :status)
      contexts = ManagementDiscoveryContext.where(engagement: engagement).latest_per_participant.order(:id).pluck(:id, :version)
      strategic = StrategicFinding.active.where(engagement: engagement).order(:id).pluck(:id, :version)
      initiatives = PlannedInitiative.where(engagement: engagement).order(:id).pluck(:id, :updated_at)
      Digest::SHA256.hexdigest([findings, contexts, strategic, initiatives].to_json)
    end

    def initialize(run, client)
      @run = run
      @engagement = run.engagement
      @client = client
    end

    def call
      @run.update!(status: "RUNNING", started_at: Time.current, input_digest: self.class.input_digest(@engagement))
      items = WorkItems.call(@run.company)
      classified = classify(items)
      edges = current_edges(items)
      clusters, suggestions = assemble(items, edges)
      outcome = Synthesizer.call(run: @run, items: items, clusters: clusters, client: @client)
      carry_forward(outcome)
      @run.update!(
        status: outcome.status == :fallback ? "PARTIAL" : "COMPLETE", fallback_reason: outcome.reason,
        finished_at: Time.current,
        prompt_versions: @run.prompt_versions.merge("P10" => Openai::Client::PROCESS_RELATIONSHIP_PROMPT_VERSION),
        counts: @run.counts.merge(
          "work_items" => items.size, "pairs_judged" => classified.size,
          "pairs_fallen_back" => classified.count { |r| r.origin == "FALLBACK" },
          "clusters" => clusters.size, "suggested_additions" => suggestions
        )
      )
      Synthesis.changed!(@run)
      @run
    rescue StandardError => e
      Rails.logger.error("[Synthesis::Run] run=#{@run.id} #{e.class}: #{e.message}")
      @run.update_columns(status: "FAILED", error: "#{e.class}: #{e.message}".truncate(1000), finished_at: Time.current)
      raise
    end

    private

    # Stages B and C: shortlist pairs not yet judged in their current form, and
    # ask P10 about each.
    def classify(items)
      return [] if items.size < 2

      current = ProcessRelationship.current.where(engagement_id: @engagement.id)
      judged = current.pluck(:pair_digest).to_set
      # A pair the consultant settled is never put back to the model.
      settled = current.where(origin: "CONSULTANT").pluck(:from_finding_id, :to_finding_id).to_set
      pairs = Candidates.call(items, skip_digests: judged).reject { |p| settled.include?([p.a.id, p.b.id]) }
      return [] if pairs.empty?

      in_cluster = current_clusters.each_with_object({}) do |cluster, map|
        cluster.finding_ids.each { |id| map[id] = cluster.name }
      end
      RelationshipClassifier.call(run: @run, pairs: pairs, client: @client, existing_clusters: in_cluster)
    end

    # The verdicts that still describe the items as they are now.
    def current_edges(items)
      by_id = items.index_by(&:id)
      ProcessRelationship.current.where(engagement_id: @engagement.id).filter_map do |relationship|
        a = by_id[relationship.from_finding_id]
        b = by_id[relationship.to_finding_id]
        next unless a && b
        next unless relationship.origin == "CONSULTANT" || relationship.pair_digest == Candidates.digest_for(a, b)

        Edge.from(relationship)
      end
    end

    # Stages D and E: rebuild the AI's clusters from the verdicts, leave the
    # consultant's alone, and work out each changed cluster's effort.
    def assemble(items, edges)
      existing = current_clusters
      locked, previous = existing.partition(&:consultant_owned?)
      result = ClusterAssembler.call(
        items: items, edges: edges,
        locked: locked.map { |c| { key: c.cluster_key, item_ids: c.finding_ids } },
        previous: previous.map { |c| { key: c.cluster_key, item_ids: c.finding_ids } },
        taken_keys: SynthesisCluster.where(engagement_id: @engagement.id).distinct.pluck(:cluster_key)
      )
      by_id = items.index_by(&:id)

      kept = SynthesisCluster.transaction do
        stored = result.groups.map { |group| store_cluster(group, previous, by_id, edges) }
        (previous - stored).each { |cluster| cluster.update!(status: "SUPERSEDED") }
        stored
      end
      suggestions = result.suggestions.map do |s|
        { "cluster_key" => s.cluster_key, "finding_id" => s.item_id, "relationship" => s.edge.relationship_type,
          "rationale" => s.edge.rationale }
      end
      [locked + kept, suggestions]
    end

    def store_cluster(group, previous, by_id, edges)
      members = group.item_ids.map { |id| by_id[id] }
      attrs = cluster_attrs(group, members)
      existing = previous.find { |c| c.cluster_key == group.key }
      if existing && existing.finding_ids.sort == group.item_ids && unchanged?(existing, attrs, members)
        return existing
      end

      cluster = if existing
                  existing.revise!(attrs.merge("synthesis_run_id" => @run.id)).tap do |c|
                    c.members.destroy_all
                    c.effort_normalization&.destroy!
                    c.reload
                  end
                else
                  SynthesisCluster.create!(attrs.merge("company_id" => @run.company_id, "engagement_id" => @engagement.id,
                                                     "synthesis_run_id" => @run.id, "cluster_key" => group.key,
                                                     "schema_version" => SynthesisCluster::SCHEMA_VERSION))
                end
      variant_of = Array(group.variants).each_with_object({}) { |v, map| v["item_ids"].each { |id| map[id] = v["label"] } }
      members.each do |item|
        cluster.members.create!(finding_id: item.id, employee_id: item.employee_id, variant_label: variant_of[item.id],
                                member_digest: item.digest)
      end
      normalise!(cluster, members, edges)
      cluster.reload
    end

    def cluster_attrs(group, members)
      {
        "name" => group.name, "cluster_type" => group.cluster_type, "status" => "PROVISIONAL", "origin" => "AI",
        "departments" => members.map(&:department).compact.uniq, "roles" => members.map(&:role).compact.uniq,
        "variants" => group.variants, "stages" => group.stages, "single_member" => group.single_member,
        "confidence" => group.confidence, "rationale" => group.rationale,
        "evidence" => members.flat_map(&:evidence).uniq
      }
    end

    def unchanged?(cluster, attrs, members)
      attrs.except("evidence").all? { |k, v| cluster[k] == v } &&
        cluster.members.map(&:member_digest).sort == members.map(&:digest).sort
    end

    def normalise!(cluster, members, edges)
      ids = members.map(&:id)
      inside = edges.select { |e| ids.include?(e.from_id) && ids.include?(e.to_id) }
      result = EffortNormalizer.call(items: members, edges: inside)
      cluster.create_effort_normalization!(
        company_id: @run.company_id, engagement_id: @engagement.id,
        raw_min: result.raw_min, raw_max: result.raw_max, dedup_min: result.dedup_min, dedup_max: result.dedup_max,
        overlap_adjustments: result.overlap_adjustments, conservative_adjustment: result.conservative_adjustment,
        double_count_warning: result.double_count_warning, warning_reason: result.warning_reason,
        duplication_flag: result.duplication_flag, participants_counted: result.participants_counted,
        method_version: EffortNormalizer::METHOD_VERSION, confidence: result.confidence
      )
    end

    def current_clusters
      @current_clusters = nil if @current_clusters&.any?(&:superseded?)
      @current_clusters ||= SynthesisCluster.current.where(engagement_id: @engagement.id).where.not(status: "REJECTED")
                                          .includes(:members, :effort_normalization).order(:id).to_a
    end

    # Consultant content survives regeneration (Doc 06 §1.2): an approved
    # operating picture is carried into the new run. When P11 could not be used,
    # the last run's synthesis is carried too, so the latest run always shows
    # the latest synthesis there is.
    def carry_forward(outcome)
      previous = SynthesisRun.where(engagement: @engagement).finished.where.not(id: @run.id).order(version: :desc).first
      return unless previous

      changes = {}
      if previous.operating_picture_status == "APPROVED"
        changes[:consultant_operating_picture] = previous.consultant_operating_picture
        changes[:operating_picture_status] = "APPROVED"
      end
      if outcome.status == :fallback
        changes.merge!(operating_picture: previous.operating_picture, initiative_conflicts: previous.initiative_conflicts,
                       role_potential: previous.role_potential, coverage_notes: previous.coverage_notes,
                       confidence: previous.confidence)
      end
      @run.update!(changes) if changes.any?
    end
  end
end
