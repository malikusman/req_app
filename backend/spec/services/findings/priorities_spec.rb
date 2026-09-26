# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::Priorities do
  let(:company) { create(:company, :onboarded, company_profile: { "business_goals" => ["Faster month-end close"] }) }
  let(:client) { instance_double(Openai::Client, configured?: true) }

  def f(id, title, role, department, hours)
    { "id" => id, "title" => title, "role" => role, "department" => department, "friction" => "#{title} is slow",
      "effort_type" => "active", "hours_min" => hours&.first, "hours_max" => hours&.last }
  end

  let(:view) do
    { "departments" => [
      { "name" => "Procurement", "roles" => [{ "title" => "Procurement Officer", "findings" => [
        f(1, "Supplier price updates", "Procurement Officer", "Procurement", [160, 240]),
        f(2, "Supplier follow-up", "Procurement Officer", "Procurement", [80, 180])
      ] }] },
      { "name" => "Sales", "roles" => [{ "title" => "Sales Coordinator", "findings" => [
        f(3, "Customer orders", "Sales Coordinator", "Sales", [500, 510])
      ] }] },
      { "name" => "Finance", "roles" => [{ "title" => "Finance Manager", "findings" => [
        f(4, "Month-end close", "Finance Manager", "Finance", [190, 195]),
        f(5, "Visa renewals", "Finance Manager", "Finance", nil)
      ] }] }
    ] }
  end

  before do
    allow(Openai::Client).to receive(:new).and_return(client)
    # The suite switches report writing off by default (spec/support/report_narrative.rb).
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_REPORT_NARRATIVE", "true").and_return("true")
  end

  def with_themes(priorities)
    allow(client).to receive(:finding_priorities).and_return("priorities" => priorities)
    described_class.call(company: company, view: view)
  end

  it "sums each theme's hours from the findings it names and ranks by them" do
    result = with_themes([
      { "title" => "Month-end figures assembled by hand", "what" => "Consolidation is manual.",
        "finding_ids" => [4], "serves_goal" => "faster month-end close" },
      { "title" => "Supplier and customer data re-keyed by hand", "what" => "The same data is typed twice.",
        "finding_ids" => [1, 3] }
    ])

    expect(result.map { |p| p["title"] }).to eq(["Supplier and customer data re-keyed by hand",
                                                 "Month-end figures assembled by hand"])
    expect(result.first).to include("rank" => 1, "hours_min" => 660, "hours_max" => 750,
                                    "roles" => ["Procurement Officer", "Sales Coordinator"])
    expect(result.last["serves_goal"]).to eq("Faster month-end close")
  end

  it "ignores ids it was not given and lets each finding sit in one theme only" do
    result = with_themes([
      { "title" => "Supplier work done twice over", "what" => "Prices and chasing.", "finding_ids" => [1, 2, 99] },
      { "title" => "Price sheets retyped by hand", "what" => "Prices again.", "finding_ids" => [1] }
    ])

    expect(result.size).to eq(1)
    expect(result.first["finding_ids"]).to eq([1, 2])
  end

  it "drops a theme that describes a solution or carries its own numbers" do
    result = with_themes([
      { "title" => "Automate supplier price updates", "what" => "Use a tool.", "finding_ids" => [1] },
      { "title" => "Orders retyped by hand", "what" => "About 500 hours go here.", "finding_ids" => [3] },
      { "title" => "Month-end figures assembled by hand", "what" => "Consolidation is manual.", "finding_ids" => [4] }
    ])

    expect(result.map { |p| p["title"] }).to eq(["Month-end figures assembled by hand"])
  end

  it "falls back to the largest findings when nothing usable comes back" do
    result = with_themes([])

    expect(result.map { |p| p["title"] }).to eq(["Customer orders", "Supplier price updates", "Month-end close",
                                                 "Supplier follow-up"])
    expect(result.first).to include("hours_min" => 500, "finding_ids" => [3])
  end

  it "falls back without a model" do
    allow(client).to receive(:configured?).and_return(false)
    expect(described_class.call(company: company, view: view).first["title"]).to eq("Customer orders")
  end
end
