# frozen_string_literal: true

module Synthesis
  # What the consultant sees of synthesis (Doc 10 §17.1): what was grouped and
  # why, raw against de-duplicated effort, variants, double-count warnings,
  # single-participant clusters, the pairs the model couldn't settle, the
  # opportunities and root causes, a verdict on each leadership concern beside
  # how much leadership said it mattered, and the operating picture — without
  # reading a transcript.
  #
  # Work is shown by role and department, never by name. Consultant-only.
  class ConsultantView
    def initialize(engagement)
      @engagement = engagement
      @company = engagement.company
    end

    def json
      status = Status.for(@engagement)
      run = status["latest_finished_run"]
      @items = WorkItems.call(@company).index_by(&:id)
      {
        "status" => status["state"], "review" => status["review"],
        "run" => run && run_json(run, status["latest_run"]),
        "clusters" => clusters.map { |c| cluster_json(c) },
        "pairs_to_review" => pairs_to_review,
        "opportunities" => current(ConsultancyOpportunity).order(:id).map { |o| opportunity_json(o) },
        "root_causes" => current(RootCause).order(:id).map { |r| root_cause_json(r) },
        "validations" => validations,
        "strategic_findings_without_verdict" => strategic_findings_without_verdict,
        "operating_picture" => run && {
          "proposed" => run.operating_picture, "consultant" => run.consultant_operating_picture,
          "status" => run.operating_picture_status
        },
        "initiative_conflicts" => run&.initiative_conflicts || [],
        "role_potential" => run&.role_potential || [],
        "decisions" => SynthesisDecision.where(engagement: @engagement).order(created_at: :desc).limit(20).map do |d|
          { "action" => d.action, "rationale" => d.rationale, "subject_type" => d.subject_type, "at" => d.created_at }
        end
      }
    end

    private

    def current(model) = model.current.where(engagement_id: @engagement.id)

    def run_json(run, latest)
      {
        "id" => run.id, "version" => run.version, "status" => run.status, "trigger" => run.trigger,
        "finished_at" => run.finished_at,
        "fallback_reason" => run.fallback_reason, "confidence" => run.confidence, "coverage_notes" => run.coverage_notes,
        "validator_drops" => run.validation_drops.size, "counts" => run.counts.except("suggested_additions"),
        "suggested_additions" => Array(run.counts["suggested_additions"]).map do |s|
          s.merge("finding" => member_json(s["finding_id"]))
        end,
        "queued" => latest&.status.in?(%w[QUEUED RUNNING]) ? latest.status : nil
      }
    end

    def clusters
      current(SynthesisCluster).where.not(status: "REJECTED").includes(:members, :effort_normalization).order(:id)
    end

    def cluster_json(cluster)
      n = cluster.effort_normalization
      member_items = cluster.finding_ids.filter_map { |id| @items[id] }
      {
        "id" => cluster.id, "key" => cluster.cluster_key, "version" => cluster.version, "status" => cluster.status,
        "origin" => cluster.origin, "name" => cluster.name, "type" => cluster.cluster_type,
        "departments" => cluster.departments, "roles" => cluster.roles, "single_member" => cluster.single_member,
        "confidence" => cluster.confidence, "why" => cluster.rationale, "variants" => cluster.variants,
        "stages" => cluster.stages,
        "members" => cluster.members.map { |m| member_json(m.finding_id).merge("variant" => m.variant_label, "stale" => m.stale?) },
        "effort" => n && {
          "raw_min" => n.raw_min&.to_f, "raw_max" => n.raw_max&.to_f, "dedup_min" => n.dedup_min&.to_f,
          "dedup_max" => n.dedup_max&.to_f, "hours_min" => n.hours_min&.to_f, "hours_max" => n.hours_max&.to_f,
          "overridden" => n.overridden?, "override_rationale" => n.override_rationale,
          "conservative" => n.conservative_adjustment, "double_count_warning" => n.double_count_warning,
          "warning_reason" => n.warning_reason, "duplication" => n.duplication_flag,
          "adjustments" => n.overlap_adjustments
        },
        "sampling" => sampling(cluster, member_items)
      }
    end

    # Who a deep dive into this would need, by role.
    def sampling(cluster, member_items)
      result = Sampling.call(cluster: cluster, items: member_items)
      role_of = member_items.to_h { |i| [i.employee_id, [i.role, i.department].compact.join(", ")] }
      {
        "recommended" => result["coverage_reason"].map { |c| { "role" => role_of[c["participant_id"]], "covers" => c["covers"] } },
        "not_needed" => result["participants_not_needed"].size
      }
    end

    def member_json(finding_id)
      item = @items[finding_id]
      return { "finding_id" => finding_id, "title" => "No longer a live finding" } unless item

      { "finding_id" => item.id, "title" => item.title, "role" => item.role, "department" => item.department,
        "hours_min" => item.hours_min, "hours_max" => item.hours_max, "effort_type" => item.effort_type,
        "single_occupant_role" => item.single_occupant_role }
    end

    def pairs_to_review
      current(ProcessRelationship).select(&:needs_review?).filter_map do |r|
        next unless @items[r.from_finding_id] && @items[r.to_finding_id]

        { "id" => r.id, "relationship_type" => r.relationship_type, "recommendation" => r.recommendation,
          "confidence" => r.confidence, "origin" => r.origin, "rationale" => r.rationale,
          "clarification" => r.clarification, "variant_assessment" => r.variant_assessment,
          "a" => member_json(r.from_finding_id), "b" => member_json(r.to_finding_id) }
      end
    end

    def opportunity_json(o)
      o.attributes.slice("id", "opportunity_key", "version", "status", "origin", "level", "category", "title",
                         "problem_statement", "evidence_summary", "affected_cluster_keys", "affected_finding_ids",
                         "affected_departments", "root_cause_key", "capacity_reference", "other_value",
                         "intervention_direction", "ai_relevance", "ai_note", "management_alignment",
                         "planned_initiative_conflict", "dependencies", "recommended_next_action", "priority_reason",
                         "management_importance", "platform_priority", "confidence")
    end

    def root_cause_json(r)
      r.attributes.slice("id", "root_cause_key", "version", "status", "statement", "explains", "affected_departments",
                         "supporting_signals", "fact_status", "confidence", "what_would_confirm")
    end

    def validations
      current(ManagementValidation).includes(strategic_finding: :management_discovery_context).order(:id).map do |v|
        sf = v.strategic_finding
        v.attributes.slice("id", "version", "status", "management_view", "what_evidence_shows", "relationship",
                           "material", "note", "resolution", "evidence")
         .merge("strategic_finding" => { "id" => sf.id, "statement" => sf.statement, "category" => sf.category,
                                         "management_importance" => sf.management_importance,
                                         "persona" => sf.management_discovery_context&.persona,
                                         "validation_need" => sf.validation_need },
                "fact_status" => v.fact_status)
      end
    end

    def strategic_findings_without_verdict
      judged = current(ManagementValidation).pluck(:strategic_finding_id)
      StrategicFinding.active.where(engagement: @engagement).where.not(id: judged).order(:id).map do |sf|
        { "id" => sf.id, "statement" => sf.statement, "management_importance" => sf.management_importance }
      end
    end
  end
end
