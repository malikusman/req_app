# frozen_string_literal: true

module Synthesis
  # A consultant's decision on synthesis (Doc 10 §17.2, Doc 05 §9.2): approve,
  # split, merge, change variants, override effort, reclassify, add, defer,
  # reject, resolve or ask about. Every decision:
  #
  #   - needs a reason, and is logged with the version it acted on and the one
  #     it made (SynthesisDecision);
  #   - makes new versions and never edits one in place (Doc 06 §1.2);
  #   - acts only on the current version — a decision on one already superseded
  #     is refused, so two consultants can't overwrite each other unseen;
  #   - fixes the grouping it expresses: splitting or rejecting a cluster also
  #     records that its items are separate, so the next run does not regroup
  #     them; merging records that they belong together;
  #   - asks for the reruns it needs — a change to a cluster or its effort
  #     re-normalises it here and queues synthesis, so task intelligence re-ranks
  #     on the new figures (Doc 10 §17).
  class Decide
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: :unprocessable_entity)
        super(message)
        @status = status
      end
    end

    RERUN_WAIT = 2.minutes
    SUBJECTS = {
      "cluster" => ProcessCluster, "opportunity" => ConsultancyOpportunity, "root_cause" => RootCause,
      "validation" => ManagementValidation, "relationship" => ProcessRelationship, "run" => SynthesisRun
    }.freeze
    ACTIONS = {
      "APPROVE_CLUSTER" => "cluster", "REJECT_CLUSTER" => "cluster", "SPLIT_CLUSTER" => "cluster",
      "MERGE_CLUSTERS" => "cluster", "CHANGE_VARIANT" => "cluster", "OVERRIDE_EFFORT" => "cluster",
      "APPROVE_OPPORTUNITY" => "opportunity", "RECLASSIFY_OPPORTUNITY" => "opportunity", "DEFER" => "opportunity",
      "REJECT_OPPORTUNITY" => "opportunity", "ADD_OPPORTUNITY" => nil,
      "APPROVE_ROOT_CAUSE" => "root_cause", "REJECT_ROOT_CAUSE" => "root_cause",
      "APPROVE_VALIDATION" => "validation", "RESOLVE_VALIDATION" => "validation",
      "REQUEST_CLARIFICATION" => "validation",
      "EDIT_OPERATING_PICTURE" => "run", "APPROVE_OPERATING_PICTURE" => "run",
      "CLASSIFY_PAIR" => "relationship"
    }.freeze
    RECLASSIFIABLE = %w[level category recommended_next_action root_cause_key title problem_statement
                        intervention_direction].freeze

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(engagement:, actor:, action:, rationale:, subject_id: nil, params: {})
      @engagement = engagement
      @actor = actor
      @action = action.to_s
      @rationale = rationale.to_s.strip
      @subject_id = subject_id
      @params = params.to_h.deep_stringify_keys
    end

    def call
      raise Error, "Unknown action" unless ACTIONS.key?(@action)
      raise Error, "Say why" if @rationale.blank?

      ActiveRecord::Base.transaction do
        @subject = load_subject
        before = @subject&.id
        after, effort_changed = send(@action.downcase)
        SynthesisDecision.create!(
          company: @engagement.company, engagement: @engagement, action: @action, subject: after || @subject,
          before_version_id: before, after_version_id: after&.id, rationale: @rationale, actor: @actor,
          details: @params.except("rationale"), rerun_scope: effort_changed ? { "effort" => true, "synthesis" => true } : {}
        )
        @rerun = effort_changed
        after
      end.tap { rerun! }
    end

    private

    # -- Clusters -------------------------------------------------------------------

    def approve_cluster
      [@subject.revise!(status: "APPROVED", fact_status: "CONSULTANT_CONFIRMED", decided_by: @actor,
                        decision_rationale: @rationale), false]
    end

    def reject_cluster
      keep_apart(@subject.finding_ids)
      [@subject.revise!(status: "REJECTED", decided_by: @actor, decision_rationale: @rationale), true]
    end

    # groups: the member finding ids in two or more parts. The first part keeps
    # the cluster's key; each further part of two or more becomes a new cluster
    # whose lineage points back here; a lone item simply leaves.
    def split_cluster
      groups = Array(@params["groups"]).map { |g| Array(g).map(&:to_i) }.reject(&:empty?)
      members = @subject.finding_ids.sort
      raise Error, "Split into at least two parts" if groups.size < 2
      raise Error, "Each item must go in exactly one part" unless groups.flatten.sort == members

      groups.combination(2).each { |a, b| keep_apart(a, b) }
      first, *rest = groups
      kept = rebuild(@subject.revise!(consultant_attrs), first)
      rest.select { |g| g.size > 1 }.each do |group|
        cluster = ProcessCluster.create!(
          @subject.attributes.slice("company_id", "engagement_id", "cluster_type", "departments", "roles", "schema_version")
                  .merge(consultant_attrs).merge("cluster_key" => next_cluster_key, "name" => "#{@subject.name} (split)",
                                                 "parent_version_id" => @subject.id, "variants" => [], "stages" => [])
        )
        rebuild(cluster, group)
      end
      [kept, true]
    end

    # Into this cluster: other clusters (cluster_ids) and/or single items
    # (finding_ids) — for instance a suggested newcomer. The merged clusters are
    # superseded, pointing at the combined one through the decision log.
    def merge_clusters
      others = ProcessCluster.current.where(engagement: @engagement, id: Array(@params["cluster_ids"])).to_a
      extra = Array(@params["finding_ids"]).map(&:to_i)
      raise Error, "Choose clusters or items to merge in" if others.empty? && extra.empty?

      live = @engagement.company.findings.live.where(id: extra).pluck(:id)
      raise Error, "Some items are not live findings of this company" unless live.sort == extra.uniq.sort

      ids = (@subject.finding_ids + others.flat_map(&:finding_ids) + extra).uniq
      keep_together(ids)
      others.each { |o| o.update!(status: "SUPERSEDED") }
      [rebuild(@subject.revise!(consultant_attrs), ids), true]
    end

    # variants: [{ "label" => "Export", "item_ids" => [..] }, ...] covering every member.
    def change_variant
      variants = Array(@params["variants"]).map do |v|
        { "label" => v["label"].to_s.strip.presence || raise(Error, "Name each variant"),
          "item_ids" => Array(v["item_ids"]).map(&:to_i),
          "distinguishing_factors" => Array(v["distinguishing_factors"]), "material_differences" => Array(v["material_differences"]) }
      end
      raise Error, "Every item needs exactly one variant" unless variants.flat_map { |v| v["item_ids"] }.sort == @subject.finding_ids.sort

      cluster = @subject.revise!(consultant_attrs.merge("variants" => variants.size > 1 ? variants : [],
                                                        "cluster_type" => variants.size > 1 ? "SHARED_VARIANT" : "SHARED_IDENTICAL"))
      labels = variants.each_with_object({}) { |v, map| v["item_ids"].each { |id| map[id] = v["label"] } }
      cluster.members.each { |m| m.update!(variant_label: variants.size > 1 ? labels[m.finding_id] : nil) }
      [cluster, false]
    end

    def override_effort
      min = Float(@params["min"], exception: false)
      max = Float(@params["max"], exception: false)
      raise Error, "Give the corrected range in hours a year" if min.nil? || max.nil?

      cluster = @subject.revise!(consultant_attrs)
      normalization = cluster.effort_normalization || raise(Error, "This cluster has no effort to override")
      normalization.update!(consultant_min: min, consultant_max: max, override_rationale: @rationale)
      [cluster, true]
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    # -- Opportunities, root causes, verdicts ----------------------------------------

    def approve_opportunity = [@subject.revise!(status: "APPROVED"), false]
    def defer = [@subject.revise!(status: "DEFERRED"), false]
    def reject_opportunity = [@subject.revise!(status: "REJECTED"), false]

    def reclassify_opportunity
      changes = @params.slice(*RECLASSIFIABLE).transform_values { |v| v.to_s.strip.presence }.compact
      raise Error, "Nothing to change" if changes.empty?

      [@subject.revise!(changes.merge("status" => "APPROVED")), false]
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    def add_opportunity
      attrs = @params.slice("level", "category", "title", "problem_statement", "intervention_direction",
                            "recommended_next_action", "affected_cluster_keys", "affected_departments")
      opportunity = ConsultancyOpportunity.create!(
        attrs.merge(company: @engagement.company, engagement: @engagement, origin: "CONSULTANT", status: "APPROVED",
                    confidence: @params["confidence"].presence || "MEDIUM",
                    recommended_next_action: attrs["recommended_next_action"].presence || "DIRECT_FINDING",
                    opportunity_key: next_key(ConsultancyOpportunity, :opportunity_key, "op"),
                    management_importance: nil, platform_priority: nil,
                    schema_version: ConsultancyOpportunity::SCHEMA_VERSION)
      )
      [opportunity, false]
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    def approve_root_cause = [@subject.revise!(status: "APPROVED", fact_status: "CONSULTANT_CONFIRMED"), false]
    def reject_root_cause = [@subject.revise!(status: "REJECTED"), false]

    def approve_validation = [@subject.revise!(status: "APPROVED"), false]

    # The consultant settles a difference: optionally a corrected verdict, and
    # what they concluded. The original conflict stays in the earlier version.
    def resolve_validation
      changes = { "status" => "RESOLVED", "resolution" => @params["resolution"].presence || @rationale }
      if @params["relationship"].present?
        raise Error, "Unknown verdict" unless ManagementValidation::RELATIONSHIPS.include?(@params["relationship"])

        changes["relationship"] = @params["relationship"]
      end
      changes["material"] = ActiveModel::Type::Boolean.new.cast(@params["material"]) if @params.key?("material")
      [@subject.revise!(changes), false]
    end

    def request_clarification
      question = @params["question"].to_s.strip
      raise Error, "Say what to ask" if question.blank?

      [@subject.revise!(status: "CLARIFY", resolution: question), false]
    end

    # -- The operating picture -------------------------------------------------------

    def edit_operating_picture
      picture = @params["operating_picture"]
      raise Error, "Give the picture" unless picture.is_a?(Hash) && picture["how_the_business_runs"].present?

      @subject.update!(consultant_operating_picture: picture, operating_picture_status: "APPROVED")
      [@subject, false]
    end

    def approve_operating_picture
      raise Error, "There is no picture to approve" if @subject.display_operating_picture.blank?

      @subject.update!(consultant_operating_picture: @subject.display_operating_picture,
                       operating_picture_status: "APPROVED")
      [@subject, false]
    end

    # -- A pair the model couldn't settle ---------------------------------------------

    def classify_pair
      type = @params["relationship_type"]
      raise Error, "Unknown relationship" unless ProcessRelationship::TYPES.include?(type)

      same = ProcessRelationship::SAME_EXECUTION.include?(@params["same_execution"]) ? @params["same_execution"] : "NO"
      together = ActiveModel::Type::Boolean.new.cast(@params["together"])
      [consultant_edge(@subject.from_finding_id, @subject.to_finding_id, type: type, same_execution: same,
                                                                         together: together), true]
    end

    # -- Shared -----------------------------------------------------------------------

    def load_subject
      kind = ACTIONS[@action]
      return nil if kind.nil?

      model = SUBJECTS.fetch(kind)
      record = model.where(engagement_id: @engagement.id).find_by(id: @subject_id)
      raise Error.new("Not found", status: :not_found) unless record
      if record.respond_to?(:superseded?) && record.superseded?
        raise Error.new("This has changed since you opened it — reload and decide on the current version",
                        status: :conflict)
      end
      if record.is_a?(ProcessRelationship) && record.status != "CURRENT"
        raise Error.new("This pair has been judged again — reload", status: :conflict)
      end

      record
    end

    def consultant_attrs
      { "status" => "APPROVED", "origin" => "CONSULTANT", "fact_status" => "CONSULTANT_CONFIRMED",
        "decided_by" => @actor, "decision_rationale" => @rationale }
    end

    # Members as given, with effort worked out again from the current verdicts.
    def rebuild(cluster, ids)
      items = WorkItems.call(@engagement.company).select { |i| ids.include?(i.id) }
      cluster.members.where.not(finding_id: ids).destroy_all
      existing = cluster.members.pluck(:finding_id)
      items.reject { |i| existing.include?(i.id) }.each do |item|
        cluster.members.create!(finding_id: item.id, employee_id: item.employee_id, member_digest: item.digest)
      end
      cluster.update!(single_member: items.map(&:employee_id).compact.uniq.size <= 1,
                      departments: items.map(&:department).compact.uniq, roles: items.map(&:role).compact.uniq)
      edges = ProcessRelationship.current.where(engagement_id: @engagement.id, from_finding_id: ids, to_finding_id: ids)
                                 .map { |r| Edge.from(r) }
      result = EffortNormalizer.call(items: items, edges: edges)
      cluster.effort_normalization&.destroy!
      cluster.create_effort_normalization!(
        company_id: cluster.company_id, engagement_id: cluster.engagement_id,
        raw_min: result.raw_min, raw_max: result.raw_max, dedup_min: result.dedup_min, dedup_max: result.dedup_max,
        overlap_adjustments: result.overlap_adjustments, conservative_adjustment: result.conservative_adjustment,
        double_count_warning: result.double_count_warning, warning_reason: result.warning_reason,
        duplication_flag: result.duplication_flag, participants_counted: result.participants_counted,
        method_version: EffortNormalizer::METHOD_VERSION, confidence: result.confidence
      )
      cluster.reload
    end

    # Records the consultant's view that items are separate, so a later run
    # keeps them apart.
    def keep_apart(ids, others = nil)
      pairs = others ? ids.product(others) : ids.combination(2).to_a
      pairs.each { |a, b| consultant_edge(a, b, type: "INDEPENDENT", same_execution: "NO", together: false) }
    end

    # ...and that items belong together, each counting for their own part.
    def keep_together(ids)
      ids.combination(2).each do |a, b|
        current = ProcessRelationship.current.find_by(engagement_id: @engagement.id, from_finding_id: [a, b].min,
                                                      to_finding_id: [a, b].max)
        next if current&.clusters?

        consultant_edge(a, b, type: "SAME_PROCESS", same_execution: current&.same_execution || "NO", together: true)
      end
    end

    def consultant_edge(a, b, type:, same_execution:, together:)
      from, to = [a, b].minmax
      previous = ProcessRelationship.current.where(engagement_id: @engagement.id, from_finding_id: from, to_finding_id: to)
                                    .order(:version).last
      previous&.update!(status: "SUPERSEDED")
      ProcessRelationship.create!(
        company: @engagement.company, engagement: @engagement, from_finding_id: from, to_finding_id: to,
        pair_digest: previous&.pair_digest || "consultant:#{from}:#{to}", version: (previous&.version || 0) + 1,
        parent_version_id: previous&.id, status: "CURRENT", origin: "CONSULTANT",
        relationship_type: type, same_execution: same_execution, confidence: "HIGH",
        recommendation: together ? "PROVISIONAL_CLUSTER" : "KEEP_SEPARATE", rationale: @rationale,
        schema_version: ProcessRelationship::SCHEMA_VERSION
      )
    end

    def next_cluster_key = next_key(ProcessCluster, :cluster_key, "cl-c")

    def next_key(model, column, prefix)
      used = model.where(engagement_id: @engagement.id).pluck(column).filter_map { |k| k.to_s[/\A#{prefix}-(\d+)\z/, 1]&.to_i }
      "#{prefix}-#{(used.max || 0) + 1}"
    end

    def rerun!
      return unless @rerun

      latest = SynthesisRun.latest_finished(@engagement)
      Synthesis.changed!(latest, effort_changed: true, reason: @action) if latest
      SynthesisRunJob.request(@engagement, trigger: "CONSULTANT", wait: RERUN_WAIT)
    end
  end
end
