# frozen_string_literal: true

require "rails_helper"

# How readily a pattern forms is a product-judgement call about false positives
# on small samples, so the shipped numbers are defaults a company can override
# rather than a decision baked into the code.
RSpec.describe "Pattern thresholds" do
  let(:company) { create(:company) }

  def signal!(type:, strength:, departments: [], label: type.humanize)
    company.company_signals.create!(
      signal_type: type, label: label, strength: strength, departments: departments,
      evidence_count: 4, first_seen_at: Time.current, last_updated_at: Time.current
    )
  end

  def thresholds!(values)
    company.update!(settings: company.settings.merge("pattern_thresholds" => values))
  end

  def patterns
    Intelligence::PatternDetector.call(company: company.reload)
  end

  it "uses the shipped defaults when a company overrides nothing" do
    signal!(type: "manual_process", strength: 0.28, departments: %w[finance operations])

    # 0.28 clears the cross-department floor (0.2) but not min_strength (0.35).
    expect(patterns.map { |p| p[:title] }).to eq(["Manual process across departments"])
  end

  it "honours a raised cross-department floor" do
    signal!(type: "manual_process", strength: 0.28, departments: %w[finance operations])
    thresholds!("cross_department_min_strength" => 0.5)

    expect(patterns).to be_empty
  end

  it "honours a lowered cross-department floor" do
    signal!(type: "manual_process", strength: 0.1, departments: %w[finance operations])
    thresholds!("cross_department_min_strength" => 0.05)

    expect(patterns.size).to eq(1)
  end

  it "honours a raised cap on cross-department patterns" do
    5.times do |i|
      signal!(type: %w[manual_process time_sink data_silo communication tool_dependency][i],
              strength: 0.8 - (i * 0.05), departments: %w[finance operations])
    end

    expect(patterns.count { |p| p[:title].match?(/across departments/) }).to eq(3)

    thresholds!("max_cross_department" => 5)
    expect(patterns.count { |p| p[:title].match?(/across departments/) }).to eq(5)
  end

  it "honours a raised anchor strength on the combo rules" do
    signal!(type: "manual_process", strength: 0.7)
    signal!(type: "approval_bottleneck", strength: 0.5)

    expect(patterns.map { |p| p[:title] }).to include("Approval bottleneck across manual workflows")

    thresholds!("anchor_strength" => 0.9)
    expect(patterns.map { |p| p[:title] }).not_to include("Approval bottleneck across manual workflows")
  end

  it "honours a raised min_strength, which excludes a signal from combo matching" do
    signal!(type: "manual_process", strength: 0.7)
    signal!(type: "approval_bottleneck", strength: 0.4)
    thresholds!("min_strength" => 0.6)

    expect(patterns).to be_empty
  end

  # Widest spread first, then strongest: a friction in three departments is a
  # bigger finding than a slightly stronger one in two.
  it "ranks by department spread before strength" do
    signal!(type: "manual_process", strength: 0.9, departments: %w[finance operations], label: "Two teams")
    signal!(type: "data_silo", strength: 0.5, departments: %w[finance operations sales], label: "Three teams")
    thresholds!("max_cross_department" => 1)

    expect(patterns.map { |p| p[:title] }).to eq(["Three teams across departments"])
  end
end
