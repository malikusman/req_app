# frozen_string_literal: true

require "rails_helper"

# Doc 10 §10.2 and §25: the same execution is never counted twice, genuine
# duplication counts for each person, handoffs count each side's own part,
# waiting is never effort, and an unclear overlap is counted once with a
# warning. Normalised effort never exceeds the raw sum.
RSpec.describe Synthesis::EffortNormalizer do
  def item(id, employee, hours, effort_type: "active")
    Synthesis::WorkItems::Item.new(id: id, employee_id: employee, hours_min: hours&.first&.to_f,
                                   hours_max: hours&.last&.to_f, effort_type: effort_type)
  end

  def edge(from, to, type, same_execution, confidence: "HIGH")
    Synthesis::Edge.new(from_id: from, to_id: to, relationship_type: type, same_execution: same_execution,
                        confidence: confidence, recommendation: "PROVISIONAL_CLUSTER")
  end

  def normalise(items, edges) = described_class.call(items: items, edges: edges)

  it "counts one person's work named twice once, keeping the fuller account" do
    result = normalise([item(1, 10, [100, 150]), item(2, 10, [90, 160])], [edge(1, 2, "SAME_PROCESS", "YES")])

    expect([result.raw_min, result.raw_max]).to eq([190.0, 310.0])
    expect([result.dedup_min, result.dedup_max]).to eq([90.0, 160.0])
    expect(result.conservative_adjustment).to be(false)
    expect(result.overlap_adjustments.first).to include("removed_item_id" => 1, "kept_item_id" => 2)
  end

  it "counts each person who genuinely duplicates the work, and flags the duplication" do
    result = normalise([item(1, 10, [50, 80]), item(2, 11, [40, 60])], [edge(1, 2, "DUPLICATE_WORK", "NO")])

    expect([result.dedup_min, result.dedup_max]).to eq([90.0, 140.0])
    expect(result.duplication_flag).to be(true)
    expect(result.participants_counted).to eq([10, 11])
  end

  it "counts each side of a handoff for its own part, even when the overlap is unclear" do
    result = normalise([item(1, 10, [100, 120]), item(2, 11, [60, 80])], [edge(1, 2, "PROCESS_STAGE", "UNKNOWN")])

    expect([result.dedup_min, result.dedup_max]).to eq([160.0, 200.0])
    expect(result.double_count_warning).to be(false)
  end

  it "counts two people doing the same kind of work on their own customers twice" do
    result = normalise([item(1, 10, [100, 150]), item(2, 11, [80, 120])], [edge(1, 2, "SAME_PROCESS", "NO")])

    expect([result.dedup_min, result.dedup_max]).to eq([180.0, 270.0])
  end

  it "counts an unclear overlap in the same process once, conservatively, and warns" do
    result = normalise([item(1, 10, [100, 150]), item(2, 11, [80, 120])], [edge(1, 2, "SAME_PROCESS", "UNKNOWN")])

    expect([result.dedup_min, result.dedup_max]).to eq([100.0, 150.0])
    expect(result.conservative_adjustment).to be(true)
    expect(result.double_count_warning).to be(true)
    expect(result.warning_reason).to include("unclear")
    expect(result.confidence).to eq("LOW")
  end

  it "removes a nested sub-step counted inside the larger task" do
    result = normalise([item(1, 10, [200, 260]), item(2, 10, [40, 60])], [edge(1, 2, "SHARED_SUBPROCESS", "YES")])

    expect([result.dedup_min, result.dedup_max]).to eq([200.0, 260.0])
  end

  it "never counts waiting time, and says what it left out" do
    result = normalise([item(1, 10, [100, 150]), item(2, 11, nil, effort_type: "waiting"), item(3, 12, nil)],
                       [edge(1, 2, "PROCESS_STAGE", "NO"), edge(1, 3, "SAME_PROCESS", "NO")])

    expect([result.raw_min, result.raw_max]).to eq([100.0, 150.0])
    expect([result.dedup_min, result.dedup_max]).to eq([100.0, 150.0])
    expect(result.waiting_count).to eq(1)
    expect(result.unquantified_count).to eq(1)
    expect(result.overlap_adjustments.map { |a| a["reason"] }.join).to include("waiting", "without figures")
  end

  it "follows a chain: three accounts of one execution count once" do
    result = normalise([item(1, 10, [30, 40]), item(2, 11, [50, 70]), item(3, 12, [20, 30])],
                       [edge(1, 2, "SAME_PROCESS", "YES"), edge(2, 3, "SAME_PROCESS", "YES")])

    expect([result.dedup_min, result.dedup_max]).to eq([50.0, 70.0])
    expect(result.overlap_adjustments.size).to eq(2)
  end

  it "never reports more de-duplicated effort than the raw sum" do
    rng = Random.new(42)
    50.times do
      items = (1..5).map { |id| item(id, rng.rand(1..3), [mn = rng.rand(1..100), mn + rng.rand(0..50)]) }
      edges = items.combination(2).select { rng.rand < 0.4 }.map do |a, b|
        edge(a.id, b.id, %w[SAME_PROCESS DUPLICATE_WORK PROCESS_STAGE SHARED_SUBPROCESS VARIANT].sample(random: rng),
             %w[YES NO UNKNOWN].sample(random: rng))
      end
      result = normalise(items, edges)
      expect(result.dedup_min).to be <= result.raw_min
      expect(result.dedup_max).to be <= result.raw_max
      expect(result.dedup_min).to be <= result.dedup_max
    end
  end
end
