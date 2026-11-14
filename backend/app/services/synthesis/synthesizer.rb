# frozen_string_literal: true

module Synthesis
  # Stages G and H: P11 reasons across the whole engagement — clusters, the
  # platform's de-duplicated figures, unclustered work, leadership's contexts
  # and strategic findings, planned initiatives — and produces root causes,
  # opportunities above task level, a verdict on each leadership concern, the
  # operating picture, initiative conflicts and role potential (Doc 10 §12–16).
  #
  # Its reply is checked (SynthesisValidator) before anything is stored. Then:
  #   - a consultant's decision is never undone: an opportunity, root cause or
  #     verdict they approved, deferred, rejected, resolved or wrote stays as it
  #     is, and the model's restatement of it is not proposed again;
  #   - a proposal the model still makes gets a new version only if it changed;
  #   - a proposal the model no longer makes is superseded, and kept.
  # Management importance comes from leadership's findings; platform priority
  # from Synthesis::Priority. They are never merged.
  #
  # When P11 can't be used, findings and clusters pass forward unsynthesised
  # and the run says so (P11 §9).
  class Synthesizer
    Outcome = Struct.new(:status, :reason, keyword_init: true)

    SAME = 0.5
    IMPORTANCE_ORDER = %w[LOW MEDIUM HIGH].freeze
    SUPPORT_ORDER = %w[NOT_YET_OBSERVED POINTS_ELSEWHERE PARTLY_SUPPORTED SUPPORTED].freeze

    def self.call(run:, items:, clusters:, client: Synthesis.client_for(run.company))
      new(run, items, clusters, client).call
    end

    def initialize(run, items, clusters, client)
      @run = run
      @items = items
      @clusters = clusters
      @client = client
    end

    def call
      log = RunLog.new(run: @run, stage: "P11", prompt_version: Openai::Client::SYNTHESIS_PROMPT_VERSION,
                       context_classes: ContextPack::CONTEXT_CLASSES)
      return Outcome.new(status: :skipped, reason: "nothing_to_synthesise") if @items.empty?

      @pack = ContextPack.new(@run, items: @items, clusters: @clusters)
      validated, reason, drops = from_model(log)
      @run.update!(validation_drops: Array(@run.validation_drops) + Array(drops))
      if validated
        log.record!(status: log.calls > 1 ? "RETRIED" : "OK")
        persist!(validated)
        Outcome.new(status: :complete)
      else
        log.record!(status: "FALLBACK", fallback_reason: reason)
        Outcome.new(status: :fallback, reason: reason)
      end
    end

    private

    def from_model(log)
      return [nil, "model_off", []] unless Llm::Synthesis.enabled? && @client.configured?
      return [nil, "model_unavailable", []] if OpenaiCircuitBreaker.open?

      drops = []
      2.times do
        result = @client.synthesis(system: Synthesis.system_prompt("p11_synthesis.v1.txt"), context: @pack.context)
        log.add(result)
        validator = SynthesisValidator.new(@client.parse_reply(result.content), pack: @pack)
        validated = validator.call
        return [validated, nil, drops + validator.drops]
      rescue JSON::ParserError, SynthesisValidator::Invalid => e
        drops << { "stage" => "P11", "where" => "reply", "note" => "unusable reply: #{e.message}" }
        next
      end
      [nil, "unusable_reply", drops]
    rescue Openai::Client::Error, Timeout::Error, SystemCallError, IOError => e
      Rails.logger.warn("[Synthesis::Synthesizer] run=#{@run.id} #{e.class}: #{e.message}")
      [nil, "model_error", []]
    end

    def persist!(validated)
      ActiveRecord::Base.transaction do
        @run.update!(
          operating_picture: validated["operating_picture"], initiative_conflicts: validated["initiative_conflicts"],
          role_potential: validated["role_potential"], coverage_notes: validated["coverage_notes"],
          confidence: validated["confidence"],
          prompt_versions: @run.prompt_versions.merge("P11" => Openai::Client::SYNTHESIS_PROMPT_VERSION)
        )
        validations = persist_validations(validated["validations"])
        root_cause_keys = persist_root_causes(validated["root_causes"])
        persist_opportunities(validated["opportunities"], root_cause_keys, validations)
      end
    end

    # -- Leadership versus evidence -------------------------------------------------

    def persist_validations(rows)
      current = ManagementValidation.current.where(engagement_id: @run.engagement_id).index_by(&:strategic_finding_id)
      rows.uniq { |r| r["strategic_finding"].id }.to_h do |row|
        finding = row["strategic_finding"]
        attrs = {
          "strategic_finding_version" => finding.version, "management_view" => row["management_view"],
          "what_evidence_shows" => row["what_evidence_shows"], "relationship" => row["relationship"],
          "material" => material?(row["relationship"], finding), "note" => row["note"], "evidence" => row["evidence"]
        }
        existing = current[finding.id]
        stored = if existing.nil?
                   ManagementValidation.create!(attrs.merge(common).merge("strategic_finding_id" => finding.id,
                                                                          "schema_version" => ManagementValidation::SCHEMA_VERSION))
                 elsif existing.status != "PROPOSED" || unchanged?(existing, attrs)
                   existing
                 else
                   existing.revise!(attrs.merge("synthesis_run_id" => @run.id))
                 end
        [finding.id, stored]
      end
    end

    # A difference worth the client's attention: leadership's diagnosis points
    # elsewhere, or a concern they rated highly is only partly borne out.
    def material?(relationship, finding)
      relationship == "POINTS_ELSEWHERE" ||
        (relationship == "PARTLY_SUPPORTED" && finding.management_importance == "HIGH")
    end

    # -- Root causes ------------------------------------------------------------------

    def persist_root_causes(rows)
      current = RootCause.current.where(engagement_id: @run.engagement_id).to_a
      matched = []
      keys = rows.map do |row|
        attrs = row.slice("statement", "explains", "affected_departments", "supporting_signals", "confidence",
                          "what_would_confirm", "evidence").merge("fact_status" => "INFERRED")
        existing = current.find { |rc| !matched.include?(rc) && similar?(rc.statement, row["statement"]) }
        matched << existing if existing
        upsert(RootCause, existing, attrs, key_prefix: "rc", key_column: "root_cause_key",
                                           schema: RootCause::SCHEMA_VERSION).root_cause_key
      end
      supersede_unmatched(current - matched)
      keys
    end

    # -- Opportunities ----------------------------------------------------------------

    def persist_opportunities(rows, root_cause_keys, validations)
      current = ConsultancyOpportunity.current.where(engagement_id: @run.engagement_id).to_a
      matched = []
      rows.each do |row|
        attrs = opportunity_attrs(row, root_cause_keys, validations)
        existing = current.find do |op|
          !matched.include?(op) && op.level == attrs["level"] &&
            (similar?(op.title, attrs["title"]) || similar?(op.problem_statement, attrs["problem_statement"]))
        end
        matched << existing if existing
        upsert(ConsultancyOpportunity, existing, attrs, key_prefix: "op", key_column: "opportunity_key",
                                                        schema: ConsultancyOpportunity::SCHEMA_VERSION)
      end
      supersede_unmatched(current - matched)
    end

    def opportunity_attrs(row, root_cause_keys, validations)
      evidence = row["evidence"]
      cluster_keys = (row["affected"] + evidence).select { |e| e["type"] == "cluster" }.map { |e| e["key"] }.uniq
      finding_ids = (row["affected"] + evidence).select { |e| e["type"] == "finding" }.map { |e| e["id"] }.uniq
      sf_ids = (evidence.select { |e| e["type"] == "strategic_finding" }.map { |e| e["id"] } +
                borne_out_by_same_work(row["affected"] + evidence, validations)).uniq
      linked = @pack.strategic_findings.select { |sf| sf_ids.include?(sf.id) }
      support = sf_ids.filter_map { |id| validations[id]&.relationship }.max_by { |r| SUPPORT_ORDER.index(r) || -1 }
      priority, reason = Priority.call(level: row["level"], confidence: row["confidence"],
                                       next_action: row["recommended_next_action"],
                                       capacity_max: capacity_max(row, cluster_keys, finding_ids),
                                       leadership_support: support)
      {
        "level" => row["level"], "category" => row["category"], "title" => row["title"],
        "problem_statement" => row["problem_statement"], "evidence_summary" => row["evidence_summary"],
        "affected_cluster_keys" => cluster_keys, "affected_finding_ids" => finding_ids,
        "affected_departments" => row["affected_departments"],
        "root_cause_key" => row["root_cause_index"] && root_cause_keys[row["root_cause_index"]],
        "capacity_reference" => row["capacity_reference"], "other_value" => row["other_value"],
        "intervention_direction" => row["intervention_direction"], "ai_relevance" => row["ai_relevance"],
        "ai_note" => row["ai_note"], "management_alignment" => row["management_alignment"],
        "planned_initiative_conflict" => row["planned_initiative_conflict"], "dependencies" => row["dependencies"],
        "recommended_next_action" => row["recommended_next_action"],
        "priority_reason" => [row["priority_reason"], reason].compact.join(" "),
        "management_importance" => linked.filter_map(&:management_importance)
                                         .max_by { |i| IMPORTANCE_ORDER.index(i) || -1 },
        "platform_priority" => priority, "platform_priority_rule_version" => Priority::RULE_VERSION,
        "strategic_finding_ids" => sf_ids, "confidence" => row["confidence"], "evidence" => evidence
      }
    end

    # Leadership concerns this opportunity answers even where P11 didn't cite
    # them: those the staff evidence bears out through the same work or
    # clusters the opportunity rests on.
    def borne_out_by_same_work(refs, validations)
      work = refs.reject { |r| r["type"] == "strategic_finding" }.map { |r| r.slice("type", "id", "key") }
      validations.filter_map do |sf_id, validation|
        next unless %w[SUPPORTED PARTLY_SUPPORTED].include?(validation.relationship)

        sf_id if Array(validation.evidence).any? { |e| work.include?(e.slice("type", "id", "key")) }
      end
    end

    # The largest platform figure behind it — quoted, or of what it affects.
    # The largest, never a sum: the figures may overlap.
    def capacity_max(row, cluster_keys, finding_ids)
      quoted = row["capacity_reference"] && @pack.figure_matching(row["capacity_reference"])
      return quoted.max if quoted

      refs = cluster_keys + finding_ids.map { |id| @pack.ref_for_finding(id) }
      @pack.figures.select { |f| refs.include?(f.ref) }.map(&:max).max
    end

    # -- Shared -----------------------------------------------------------------------

    def upsert(model, existing, attrs, key_prefix:, key_column:, schema:)
      if existing.nil?
        model.create!(attrs.merge(common).merge(key_column => next_key(model, key_column, key_prefix),
                                                "schema_version" => schema))
      elsif existing.status != "PROPOSED" || existing.origin == "CONSULTANT" || unchanged?(existing, attrs)
        existing
      else
        existing.revise!(attrs.merge("synthesis_run_id" => @run.id))
      end
    end

    # The model no longer proposes it: superseded, never deleted. A consultant's
    # own or decided rows are left alone.
    def supersede_unmatched(rows)
      rows.select { |r| r.status == "PROPOSED" && r.origin == "AI" }.each { |r| r.update!(status: "SUPERSEDED") }
    end

    def common
      { "company_id" => @run.company_id, "engagement_id" => @run.engagement_id, "synthesis_run_id" => @run.id,
        "status" => "PROPOSED", "origin" => "AI", "prompt_version" => Openai::Client::SYNTHESIS_PROMPT_VERSION }
    end

    def next_key(model, column, prefix)
      used = model.where(engagement_id: @run.engagement_id).pluck(column).map { |k| k.to_s[/\d+\z/].to_i }
      "#{prefix}-#{(used.max || 0) + 1}"
    end

    def unchanged?(record, attrs)
      attrs.all? { |k, v| normalise(record[k]) == normalise(v) }
    end

    def normalise(value)
      case value
      when Array then value.map { |v| normalise(v) }
      when Hash then value.transform_keys(&:to_s).transform_values { |v| normalise(v) }
      when BigDecimal then value.to_f
      else value
      end
    end

    def similar?(one, other)
      Findings::Words.overlap(Findings::Words.of(one), Findings::Words.of(other)) >= SAME
    end
  end
end
