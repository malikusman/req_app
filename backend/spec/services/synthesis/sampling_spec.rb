# frozen_string_literal: true

require "rails_helper"

# Doc 10 §11, D8, D9: one person is enough for shared work, one per material
# variant or stage, and nobody confirms a colleague's account.
RSpec.describe Synthesis::Sampling do
  before { stub_const("Cluster", Struct.new(:cluster_type, :variants, :stages, :confidence, keyword_init: true)) }

  def item(id, employee, hours) = Synthesis::WorkItems::Item.new(id: id, employee_id: employee, hours_min: hours,
                                                                 hours_max: hours)

  it "recommends one person for the same work done by five" do
    items = (1..5).map { |n| item(n, 100 + n, n * 10.0) }
    result = described_class.call(cluster: Cluster.new(cluster_type: "SHARED_IDENTICAL", confidence: "HIGH"),
                                  items: items)

    expect(result["recommended_participant_ids"]).to eq([105])
    expect(result["participants_not_needed"].map { |p| p["participant_id"] }).to contain_exactly(101, 102, 103, 104)
  end

  it "recommends one person per material variant" do
    items = [item(1, 10, 50.0), item(2, 11, 80.0), item(3, 12, 30.0)]
    variants = [{ "label" => "Variant A", "item_ids" => [1, 2] }, { "label" => "Variant B", "item_ids" => [3] }]
    result = described_class.call(cluster: Cluster.new(cluster_type: "SHARED_VARIANT", variants: variants),
                                  items: items)

    expect(result["recommended_participant_ids"]).to eq([11, 12])
    expect(result["variants_covered"]).to eq(["Variant A", "Variant B"])
  end

  it "recommends one short session at each stage of an end-to-end process" do
    items = [item(1, 10, 50.0), item(2, 11, 80.0)]
    stages = [{ "role" => "Sales", "item_ids" => [1] }, { "role" => "Warehouse", "item_ids" => [2] }]
    result = described_class.call(cluster: Cluster.new(cluster_type: "END_TO_END", stages: stages), items: items)

    expect(result["recommended_participant_ids"]).to eq([10, 11])
    expect(result["participants_not_needed"]).to be_empty
  end
end
