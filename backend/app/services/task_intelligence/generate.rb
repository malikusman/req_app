# frozen_string_literal: true

require "digest"

module TaskIntelligence
  class Generate
    DEFAULT_TARGET = 5
    ALGORITHM_VERSION = "2"
    EVALUATION_MODE = "deterministic"
    FOCUS_BONUS = 2

    def self.call(company:, target: DEFAULT_TARGET)
      new(company, target).call
    end

    def initialize(company, target)
      raise ArgumentError, "target must be a positive integer" unless target.is_a?(Integer) && target.positive?

      @company = company
      @target = target
    end

    def call
      # Consolidation uses the same company lock. A run sees one set of current
      # cluster revisions and cannot race another generator for its version.
      @company.with_lock do
        revisions = current_revisions
        members = memberships_for(revisions)
        eligible = revisions.select { |revision| members.key?(revision.id) }
        overlaps = overlap_links(eligible, members)
        evidence = evidence_conversations(members.values.flatten)
        goals = Array(@company.company_profile["business_goals"]).grep(String)

        rows = eligible.map do |revision|
          EvaluateCluster.new(revision: revision, memberships: members.fetch(revision.id),
                              evidence_conversations: evidence, overlaps: overlaps[revision.process_cluster_id].to_a.sort,
                              goals: goals).call.merge(cluster_id: revision.process_cluster_id)
        end

        persist(rank(rows), goals)
      end
    end

    private

    def current_revisions
      ProcessCluster.where(company: @company, active: true).order(:id).includes(:current_revision)
                    .filter_map(&:current_revision).select { |revision| revision.status == "active" }
    end

    def memberships_for(revisions)
      ProcessClusterMembership.where(process_cluster_revision: revisions)
                              .joins(:task_source).where(task_sources: { company_id: @company.id })
                              .includes(task_source: :finding).order(:id).group_by(&:process_cluster_revision_id)
    end

    def evidence_conversations(memberships)
      message_ids = memberships.flat_map { |member| member.task_source.evidence_references.pluck("message_id") }.compact
      TaskSource.evidence_messages.where(id: message_ids).pluck(:id, :conversation_id).to_h
    end

    def overlap_links(revisions, memberships)
      cluster_by_source = revisions.each_with_object({}) do |revision, index|
        memberships.fetch(revision.id).each { |member| index[member.task_source_id] = revision.process_cluster_id }
      end
      revisions.flat_map(&:relationships).each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |relationship, links|
        next unless ProcessClusters::Relationship::OVERLAP_KINDS.include?(relationship["kind"])

        left, right = relationship.fetch("source_ids").map { |id| cluster_by_source[id] }
        next unless left && right && left != right

        links[left].add(right)
        links[right].add(left)
      end
    end

    def rank(rows)
      selected = {}
      focuses = Set.new
      pool = rows.select { |row| row.dig(:assessment, "grounded_for_investigation") }

      while selected.size < @target
        available = pool.reject { |row| overlapping_selection?(row, selected) }
        best = available.max_by do |row|
          [row.fetch(:score) + diversity_bonus(row, focuses), row.fetch(:score), -row.fetch(:cluster_id)]
        end
        break unless best

        selected[best.fetch(:cluster_id)] = [selected.size + 1, diversity_bonus(best, focuses)]
        focuses.add(best.dig(:assessment, "focus"))
        pool.delete(best)
      end

      rows.map { |row| disposition(row, selected) }
    end

    def diversity_bonus(row, focuses)
      focuses.include?(row.dig(:assessment, "focus")) ? 0 : FOCUS_BONUS
    end

    def overlapping_selection?(row, selected)
      row.dig(:assessment, "potential_overlap_cluster_ids").any? { |id| selected.key?(id) }
    end

    def disposition(row, selected)
      rank, bonus = selected[row.fetch(:cluster_id)]
      assessment = row.fetch(:assessment)
      if rank
        factors = assessment.fetch("score_breakdown").sort_by { |key, value| [-value, key] }
                            .select { |_, value| value.positive? }.first(3).map { |key, _| key.tr("_", " ") }
        status = "shortlisted"
        reason = "Ranked #{rank} based on #{factors.join(', ')}."
        reason += " Added a different investigation focus." if bonus.positive?
      elsif !assessment.fetch("grounded_for_investigation")
        status = "insufficient_evidence"
        reason = "The evidence does not yet establish a concrete activity or a useful investigation objective."
      elsif overlapping_selection?(row, selected)
        status = "needs_overlap_review"
        reason = "May overlap a shortlisted cluster. Validate the boundary before investigating it separately."
      else
        status = "deferred_capacity"
        reason = "Eligible for investigation. Other candidates ranked higher within this run's target size."
      end
      if assessment.fetch("clarification_requests").any?
        reason += " Open clarification may change the effort estimate or which participants are needed."
      elsif assessment.fetch("potential_overlap_cluster_ids").any?
        reason += " The scope remains provisional until overlap is checked."
      end

      row.except(:cluster_id).merge(
        rank: rank, disposition: status, disposition_reason: reason,
        assessment: assessment.merge("diversity_bonus_at_selection" => bonus)
      )
    end

    def persist(rows, goals)
      runs = TaskIntelligenceRun.where(company: @company)
      latest = runs.order(version: :desc).first
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([ALGORITHM_VERSION, EVALUATION_MODE, @target, goals, rows]))
      return latest if latest&.fingerprint == fingerprint

      run = runs.create!(version: (latest&.version || 0) + 1, target_size: @target, fingerprint: fingerprint,
                         algorithm_version: ALGORITHM_VERSION, evaluation_mode: EVALUATION_MODE)
      rows.each { |row| run.candidates.create!(**row) }
      run
    end
  end
end
