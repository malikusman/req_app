# frozen_string_literal: true

require "digest"

module ProcessClusters
  class ReconcileClarifications
    def initialize(company:, evidence:, observations:)
      @requests = ClarificationRequest.where(company: company)
      @evidence = evidence
      @observations = observations
    end

    # Attach the open request snapshot to the relationship before the cluster
    # revision is written. Later request updates cannot change that revision.
    def call(relationships)
      comparisons = relationships.values.index_by { |relationship| pair_key(sources_for(relationship)) }
      existing = @requests.where(status: "open").or(@requests.where(pair_key: comparisons.keys)).index_by(&:pair_key)

      comparisons.each do |key, relationship|
        sources = sources_for(relationship)
        request = existing.delete(key)
        if relationship["classification"] == "UNRESOLVED"
          impacts = material_impacts(sources)
          if impacts.any?
            request ||= @requests.new(pair_key: key)
            update(request, sources, "open", open_details(sources, relationship, impacts))
            relationship["clarification_request"] = request.snapshot
          elsif request&.status == "open"
            close(request, sources, "The current uncertainty no longer affects effort or participant sampling.")
          end
        elsif request && request.status != "resolved"
          details = request.details.merge("affected_sources" => sources.map { |source| source_details(source) },
                                          "resolution" => relationship.slice("classification", "rationale"))
          update(request, sources, "resolved", details)
        end
      end

      existing.each_value do |request|
        next unless request.status == "open"

        close(request, [request.left_source, request.right_source], "The current evidence no longer supports comparing this pair.")
      end
    end

    # A partial comparison set must never close or reopen an existing request.
    # The caller holds the same company lock used by Rebuild.
    def backfill_missing(relationships)
      relationships.filter_map do |relationship|
        sources = sources_for(relationship)
        impacts = material_impacts(sources)
        next if impacts.empty?

        key = pair_key(sources)
        next if @requests.exists?(pair_key: key)

        request = @requests.new(pair_key: key)
        update(request, sources, "open", open_details(sources, relationship, impacts))
        request
      end
    end

    private

    def sources_for(relationship)
      relationship.fetch("source_ids").map { |id| @evidence.fetch(id).source }.sort_by(&:first_source_id)
    end

    def pair_key(sources)
      Digest::SHA256.hexdigest(JSON.generate(sources.map(&:first_source_id)))
    end

    def material_impacts(sources)
      impacts = []
      if sources.any? { |source| quantified_effort?(@observations.fetch(source.id)) }
        impacts << "effort_estimation"
      end
      impacts << "participant_sampling" if sources.map(&:employee_id).uniq.size > 1
      impacts
    end

    def quantified_effort?(observations)
      observations.any? do |observation|
        observation["effort_type"] != "waiting" &&
          %w[duration frequency].any? do |measure|
            observation.fetch(measure).values_at("min", "max").any? { |value| value.is_a?(Numeric) && value.positive? }
          end
      end
    end

    def open_details(sources, relationship, impacts)
      unknowns = ["Whether these sources describe the same work, variants, or distinct activities."]
      unknowns << "Whether the effort observations cover the same workload or separate work." if impacts.include?("effort_estimation")
      unknowns << "Whether one participant can describe the shared scope or separate participants are needed." if
        impacts.include?("participant_sampling")
      {
        "affected_sources" => sources.map { |source| source_details(source) },
        "missing_evidence" => relationship.fetch("missing_evidence"),
        "why_it_matters" => unknowns.drop(1),
        "unknowns" => unknowns, "impacts" => impacts,
        "rationale" => relationship.fetch("rationale")
      }
    end

    def source_details(source)
      evidence = @evidence.fetch(source.id)
      references = Relationship::SCOPE_FIELDS.filter_map do |field|
        fact = evidence.fact(field) || evidence.fact(field, status: "conflict")
        fact ||= evidence.legacy_slot("how_it_works") if field == "steps_decisions"
        next unless fact

        (fact["evidence"] || fact).slice("message_id", "turn").compact.merge("field" => field)
      end
      { "task_source_id" => source.id, "source_version" => source.version, "conversation_id" => source.conversation_id,
        "employee_id" => source.employee_id, "evidence_references" => references }
    end

    def close(request, sources, reason)
      details = request.details.merge("resolution" => { "rationale" => reason })
      if sources.all? { |source| @evidence.key?(source.id) }
        details["affected_sources"] = sources.map { |source| source_details(source) }
      end
      update(request, sources, "closed", details)
    end

    def update(request, sources, status, details)
      return if request.persisted? && request.left_source_id == sources.first.id &&
                request.right_source_id == sources.last.id && request.status == status && request.details == details

      previous = request.snapshot if request.persisted?
      request.assign_attributes(left_source: sources.first, right_source: sources.last, status: status, details: details)
      request.history += [previous] if previous
      request.version = (request.version || 0) + 1
      request.save!
      # Match the JSONB representation used on subsequent rebuilds, including
      # key ordering when the snapshot contributes to a cluster fingerprint.
      request.reload
    end
  end
end
