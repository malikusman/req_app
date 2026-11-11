# frozen_string_literal: true

module Synthesis
  # What task intelligence (Doc 11, P12) starts from — the one read of
  # synthesis it needs, as Companies::AgentContext.neutral_management_context
  # is the one read of leadership employee discovery has.
  #
  # Doc 11 §1 and §3: clusters with their variants and members, de-duplicated
  # effort to rank on (never raw sums), who a deep dive would need, unclustered
  # work, opportunities and root causes with their next step, leadership's
  # verdicts and initiative conflicts. Task intelligence reads this, never the
  # synthesis tables, so the two can change independently.
  #
  # What it carries and what it doesn't:
  #   - Status on every object. APPROVED is the consultant's; PROVISIONAL or
  #     PROPOSED is the platform's and may still change. Rejected and
  #     superseded objects are left out.
  #   - Participants by id only — this is a protected stage that may reason
  #     across participants (Doc 05 §4), never a place to show names.
  #   - Nothing consultant-private, no transcripts, no operating-picture prose.
  #
  # PROPOSED CONTRACT, version SYN-TI.v1 — to be agreed with task intelligence.
  # "member_work_item_ids" are Finding ids until employee discovery keeps
  # WorkItem records. Subscribe to "synthesis.changed" to re-rank when effort
  # moves (Doc 10 §17).
  class ForTaskIntelligence
    CONTRACT_VERSION = "SYN-TI.v1"

    def self.call(engagement) = new(engagement).call

    def initialize(engagement)
      @engagement = engagement
      @company = engagement.company
    end

    def call
      status = Status.for(@engagement)
      run = status["latest_finished_run"]
      @items = WorkItems.call(@company).index_by(&:id)
      clusters = current(ProcessCluster).where.not(status: "REJECTED").includes(:members, :effort_normalization).order(:id).to_a
      clustered = clusters.flat_map(&:finding_ids).to_set
      {
        "contract_version" => CONTRACT_VERSION,
        "synthesis_version" => run&.version, "generated_at" => run&.finished_at,
        "stale" => status["state"] == "stale",
        "clusters" => clusters.map { |c| cluster_json(c) },
        "unclustered_work_item_ids" => @items.keys.reject { |id| clustered.include?(id) },
        "opportunities" => current(ConsultancyOpportunity).where.not(status: "REJECTED").order(:id).map { |o| opportunity_json(o) },
        "root_causes" => current(RootCause).where.not(status: "REJECTED").order(:id).map do |r|
          { "key" => r.root_cause_key, "version" => r.version, "status" => r.status, "statement" => r.statement,
            "explains" => r.explains, "confidence" => r.confidence, "fact_status" => r.fact_status }
        end,
        "management_validations" => current(ManagementValidation).where.not(status: "REJECTED").order(:id).map do |v|
          { "strategic_finding_id" => v.strategic_finding_id, "status" => v.status, "relationship" => v.relationship,
            "material" => v.material, "what_evidence_shows" => v.what_evidence_shows }
        end,
        "initiative_conflicts" => run&.initiative_conflicts || []
      }
    end

    private

    def current(model) = model.current.where(engagement_id: @engagement.id)

    def cluster_json(cluster)
      n = cluster.effort_normalization
      members = cluster.finding_ids.filter_map { |id| @items[id] }
      sampling = Sampling.call(cluster: cluster, items: members)
      {
        "key" => cluster.cluster_key, "version" => cluster.version, "status" => cluster.status,
        "name" => cluster.name, "cluster_type" => cluster.cluster_type,
        "departments" => cluster.departments, "roles" => cluster.roles,
        "member_work_item_ids" => cluster.finding_ids, "participant_ids" => members.map(&:employee_id).compact.uniq,
        "variants" => cluster.variants, "stages" => cluster.stages, "single_member" => cluster.single_member,
        "effort" => n && {
          "raw_min" => n.raw_min&.to_f, "raw_max" => n.raw_max&.to_f,
          "dedup_min" => n.hours_min&.to_f, "dedup_max" => n.hours_max&.to_f,
          "conservative" => n.conservative_adjustment, "double_count_warning" => n.double_count_warning,
          "consultant_override" => n.overridden?
        },
        "sampling" => {
          "recommended_participant_ids" => sampling["recommended_participant_ids"],
          "coverage_reason" => sampling["coverage_reason"], "variants_covered" => sampling["variants_covered"],
          "not_needed" => sampling["participants_not_needed"], "confidence" => sampling["confidence"]
        },
        "confidence" => cluster.confidence, "evidence" => cluster.evidence
      }
    end

    def opportunity_json(o)
      {
        "key" => o.opportunity_key, "version" => o.version, "status" => o.status, "level" => o.level,
        "category" => o.category, "title" => o.title, "problem_statement" => o.problem_statement,
        "affected_cluster_keys" => o.affected_cluster_keys, "affected_work_item_ids" => o.affected_finding_ids,
        "root_cause_key" => o.root_cause_key, "recommended_next_action" => o.recommended_next_action,
        "management_importance" => o.management_importance, "platform_priority" => o.platform_priority,
        "planned_initiative_conflict" => o.planned_initiative_conflict, "dependencies" => o.dependencies,
        "confidence" => o.confidence
      }
    end
  end
end
