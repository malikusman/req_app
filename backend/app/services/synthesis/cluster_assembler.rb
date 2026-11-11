# frozen_string_literal: true

module Synthesis
  # Stage D: groups work items into process clusters from the judged edges,
  # without losing variants (Doc 10 §9).
  #
  #   - Only edges P10 recommended clustering on, at MEDIUM or HIGH, join items.
  #     A false merge does more damage than two related items left apart.
  #   - Variants stay inside the cluster: items joined only through a VARIANT
  #     edge are labelled as separate variants, with what distinguishes them.
  #   - A cluster a consultant approved, split, merged or created is theirs.
  #     Its members are never moved; an edge from a new item to one of them is
  #     returned as a suggestion for the consultant, not applied (Doc 10 §19,
  #     §21).
  #   - A cluster keeps its key across runs when it keeps most of its members,
  #     so a late interview extends an existing process rather than making a
  #     new one.
  class ClusterAssembler
    Group = Struct.new(:key, :item_ids, :cluster_type, :variants, :stages, :single_member, :edges, :confidence,
                       :name, :rationale, keyword_init: true)
    Suggestion = Struct.new(:cluster_key, :item_id, :edge, keyword_init: true)
    Result = Struct.new(:groups, :suggestions, keyword_init: true)

    CONFIDENCE_ORDER = %w[LOW MEDIUM HIGH].freeze

    # items: WorkItems::Item. edges: Edge. locked / previous: [{ key:, item_ids: }]
    # for consultant-owned and earlier AI clusters. taken_keys: every cluster key
    # this engagement has used, so a new key never collides with an old one.
    def self.call(items:, edges:, locked: [], previous: [], taken_keys: [])
      new(items, edges, locked, previous, taken_keys).call
    end

    def initialize(items, edges, locked, previous, taken_keys)
      @items = items.index_by(&:id)
      @edges = edges.select { |e| @items.key?(e.from_id) && @items.key?(e.to_id) && e.clusters? }
      @locked = locked.each_with_object({}) { |c, map| c[:item_ids].each { |id| map[id] = c[:key] } }
      @previous = previous
      @taken = Set.new(taken_keys)
    end

    def call
      suggestions = []
      parent = {}
      @edges.each do |edge|
        from_key = @locked[edge.from_id]
        to_key = @locked[edge.to_id]
        if from_key && to_key
          next # Both already in a consultant's clusters: theirs to merge, not ours.
        elsif from_key || to_key
          suggestions << Suggestion.new(cluster_key: from_key || to_key, item_id: from_key ? edge.to_id : edge.from_id,
                                        edge: edge)
        else
          union(parent, edge.from_id, edge.to_id)
        end
      end

      components = parent.keys.group_by { |id| find(parent, id) }.values.select { |ids| ids.size > 1 }
      used = Set.new
      groups = components.sort_by(&:min).map { |ids| group(ids.sort, used) }
      Result.new(groups: groups, suggestions: suggestions.uniq { |s| [s.cluster_key, s.item_id] })
    end

    private

    def group(ids, used)
      inside = @edges.select { |e| ids.include?(e.from_id) && ids.include?(e.to_id) }
      types = inside.map(&:relationship_type)
      variants = variants_for(ids, inside)
      members = ids.map { |id| @items[id] }
      lead = members.max_by { |i| [i.hours_max.to_f, -i.id] }
      Group.new(
        key: key_for(ids, used), item_ids: ids,
        cluster_type: if types.include?("PROCESS_STAGE") then "END_TO_END"
                      elsif variants.size > 1 then "SHARED_VARIANT"
                      else "SHARED_IDENTICAL"
                      end,
        variants: variants.size > 1 ? variants : [],
        stages: types.include?("PROCESS_STAGE") ? stages_for(members) : [],
        single_member: members.map(&:employee_id).compact.uniq.size <= 1,
        edges: inside,
        confidence: inside.map(&:confidence).min_by { |c| CONFIDENCE_ORDER.index(c) || 0 },
        name: lead.title,
        rationale: inside.max_by { |e| CONFIDENCE_ORDER.index(e.confidence) || 0 }&.rationale
      )
    end

    # Items joined by anything but a VARIANT edge share a variant; VARIANT edges
    # separate them, carrying what makes them differ.
    def variants_for(ids, inside)
      parent = ids.to_h { |id| [id, id] }
      inside.reject { |e| e.relationship_type == "VARIANT" }.each { |e| union(parent, e.from_id, e.to_id) }
      parts = ids.group_by { |id| find(parent, id) }.values.sort_by(&:min)
      return [] if parts.size < 2

      factors = inside.select { |e| e.relationship_type == "VARIANT" }.flat_map do |e|
        Array(e.variant_assessment["distinguishing_factors"]) - ["NONE"]
      end.uniq
      differences = inside.select { |e| e.relationship_type == "VARIANT" }
                          .flat_map { |e| Array(e.variant_assessment["material_differences"]) }.uniq
      parts.each_with_index.map do |part, index|
        { "label" => "Variant #{('A'.ord + index).chr}", "item_ids" => part,
          "roles" => part.map { |id| @items[id].role }.compact.uniq,
          "departments" => part.map { |id| @items[id].department }.compact.uniq,
          "distinguishing_factors" => factors, "material_differences" => differences }
      end
    end

    def stages_for(members)
      members.group_by { |i| [i.department, i.role] }.map do |(department, role), items|
        { "department" => department, "role" => role, "item_ids" => items.map(&:id) }
      end
    end

    # The earlier AI cluster this one mostly continues, or a fresh key.
    def key_for(ids, used)
      best = @previous.reject { |c| used.include?(c[:key]) }
                      .map { |c| [c[:key], (c[:item_ids] & ids).size] }
                      .select { |_, shared| shared.positive? }
                      .max_by { |key, shared| [shared, key] }
      key = best&.first || fresh_key(ids)
      used << key
      @taken << key
      key
    end

    def fresh_key(ids)
      base = "cl-#{ids.min}"
      key = base
      suffix = 1
      while @taken.include?(key)
        suffix += 1
        key = "#{base}-#{suffix}"
      end
      key
    end

    def union(parent, a, b)
      parent[a] ||= a
      parent[b] ||= b
      root_a = find(parent, a)
      root_b = find(parent, b)
      parent[root_b] = root_a unless root_a == root_b
    end

    def find(parent, x)
      parent[x] = find(parent, parent[x]) unless parent[x] == x
      parent[x]
    end
  end
end
