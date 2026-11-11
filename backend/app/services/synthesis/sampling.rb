# frozen_string_literal: true

module Synthesis
  # Stage F: the fewest people a later deep dive into a cluster needs (Doc 10
  # §11, Decision Register D8 and D9). One person per material variant, one per
  # stage of an end-to-end process; everyone else is not needed, and says why.
  # Nobody is ever asked to confirm a colleague's account.
  #
  # A recommendation only — the consultant decides, in task selection. Worked
  # out from the cluster each time it is read, so it always follows the
  # cluster's current shape.
  class Sampling
    def self.call(cluster:, items:) = new(cluster, items).call

    # cluster: anything with variants, stages, cluster_type, confidence.
    # items: WorkItems::Item for its members.
    def initialize(cluster, items)
      @cluster = cluster
      @items = items
    end

    def call
      parts = coverage_parts
      chosen = parts.map do |part|
        person = part[:items].select(&:employee_id).max_by { |i| [i.hours_max.to_f, -i.id] }
        person && { "participant_id" => person.employee_id, "covers" => part[:label] }
      end.compact.uniq { |c| c["participant_id"] }
      chosen_ids = chosen.map { |c| c["participant_id"] }

      {
        "recommended_participant_ids" => chosen_ids,
        "coverage_reason" => chosen,
        "variants_covered" => parts.map { |p| p[:label] },
        "participants_not_needed" => (@items.map(&:employee_id).compact.uniq - chosen_ids).map do |id|
          { "participant_id" => id,
            "reason" => "Does the same work as someone already recommended; one person's answers are enough" }
        end,
        "confidence" => @cluster.confidence
      }
    end

    private

    def coverage_parts
      by_id = @items.index_by(&:id)
      if @cluster.cluster_type == "END_TO_END" && Array(@cluster.stages).any?
        Array(@cluster.stages).map do |stage|
          { label: "Stage: #{[stage['role'], stage['department']].compact.join(', ')}",
            items: Array(stage["item_ids"]).filter_map { |id| by_id[id] } }
        end
      elsif Array(@cluster.variants).any?
        Array(@cluster.variants).map do |variant|
          { label: variant["label"], items: Array(variant["item_ids"]).filter_map { |id| by_id[id] } }
        end
      else
        [{ label: "Shared process", items: @items }]
      end
    end
  end
end
