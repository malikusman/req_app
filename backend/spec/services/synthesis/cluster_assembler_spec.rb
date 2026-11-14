# frozen_string_literal: true

require "rails_helper"

# Doc 10 §9, §19, §21: clusters only on edges P10 recommended at MEDIUM or
# HIGH, keeps variants inside the cluster, leaves a consultant's clusters
# alone, and keeps a cluster's identity when a late interview extends it.
RSpec.describe Synthesis::ClusterAssembler do
  def item(id, employee, role: "Sales Coordinator", department: "Sales", hours: [100, 150])
    Synthesis::WorkItems::Item.new(id: id, employee_id: employee, role: role, department: department,
                                   title: "Work #{id}", hours_min: hours.first.to_f, hours_max: hours.last.to_f,
                                   effort_type: "active")
  end

  def edge(from, to, type = "SAME_PROCESS", confidence: "HIGH", recommendation: "PROVISIONAL_CLUSTER", **rest)
    Synthesis::Edge.new(from_id: from, to_id: to, relationship_type: type, same_execution: "NO",
                        confidence: confidence, recommendation: recommendation, variant_assessment: {}, **rest)
  end

  let(:items) { [item(1, 10), item(2, 11), item(3, 12), item(4, 13)] }

  it "groups items joined by clustering edges and leaves the rest alone" do
    result = described_class.call(items: items, edges: [edge(1, 2), edge(3, 4, "INDEPENDENT", recommendation: "KEEP_SEPARATE")])

    expect(result.groups.map(&:item_ids)).to eq([[1, 2]])
    expect(result.groups.first.cluster_type).to eq("SHARED_IDENTICAL")
    expect(result.groups.first.key).to eq("cl-1")
  end

  it "never joins on a LOW-confidence or review-only edge" do
    result = described_class.call(items: items,
                                  edges: [edge(1, 2, confidence: "LOW", recommendation: "KEEP_SEPARATE"),
                                          edge(3, 4, "VARIANT", confidence: "MEDIUM", recommendation: "CONSULTANT_REVIEW")])

    expect(result.groups).to be_empty
  end

  it "keeps variants inside one cluster, saying what distinguishes them" do
    variant = edge(2, 3, "VARIANT", confidence: "MEDIUM",
                                    variant_assessment: { "distinguishing_factors" => ["LOCATION"],
                                                          "material_differences" => ["Different branch"] })
    result = described_class.call(items: items, edges: [edge(1, 2), variant])

    group = result.groups.first
    expect(group.item_ids).to eq([1, 2, 3])
    expect(group.cluster_type).to eq("SHARED_VARIANT")
    expect(group.variants.map { |v| v["item_ids"] }).to eq([[1, 2], [3]])
    expect(group.variants.first["distinguishing_factors"]).to eq(["LOCATION"])
  end

  it "makes an end-to-end process of stages, by role" do
    items = [item(1, 10, role: "Sales"), item(2, 11, role: "Warehouse", department: "Operations")]
    result = described_class.call(items: items, edges: [edge(1, 2, "PROCESS_STAGE")])

    expect(result.groups.first.cluster_type).to eq("END_TO_END")
    expect(result.groups.first.stages.map { |s| s["role"] }).to eq(%w[Sales Warehouse])
  end

  it "flags a cluster whose items all come from one person" do
    items = [item(1, 10), item(2, 10)]
    expect(described_class.call(items: items, edges: [edge(1, 2)]).groups.first.single_member).to be(true)
  end

  it "suggests, but never applies, adding a new item to a consultant's cluster" do
    result = described_class.call(items: items, edges: [edge(1, 4), edge(2, 3)],
                                  locked: [{ key: "cl-locked", item_ids: [1, 2] }])

    expect(result.groups).to be_empty
    expect(result.suggestions.map { |s| [s.cluster_key, s.item_id] }).to contain_exactly(["cl-locked", 4],
                                                                                        ["cl-locked", 3])
  end

  it "keeps a cluster's key when a late interview extends it" do
    result = described_class.call(items: items, edges: [edge(1, 2), edge(2, 3)],
                                  previous: [{ key: "cl-earlier", item_ids: [1, 2] }], taken_keys: ["cl-earlier"])

    expect(result.groups.first.key).to eq("cl-earlier")
    expect(result.groups.first.item_ids).to eq([1, 2, 3])
  end

  it "never reuses a key the engagement has already used for something else" do
    result = described_class.call(items: items, edges: [edge(1, 2)], taken_keys: ["cl-1"])

    expect(result.groups.first.key).to eq("cl-1-2")
  end
end
