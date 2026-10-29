# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::DeltaCalculator do
  let(:company) { create(:company) }

  it "returns initial summary when no previous report" do
    delta = described_class.call(company: company, previous_report: nil)
    expect(delta["summary"]).to eq("Initial discovery report").or include("Initial")
  end

  describe "what's new, from the findings" do
    let(:employee) { create(:employee, company: company) }

    before { company.update!(settings: { "report_small_roles" => "show" }) }

    def finding(key, title, department: "finance", hours: 100, status: "approved")
      company.findings.create!(employee: employee, source_key: key, area: title, title: title, department: department,
                               role_title: "Clerk", friction: "Done by hand", status: status,
                               annual_hours_min: hours, annual_hours_max: hours)
    end

    let!(:kept) { finding("k1", "Invoice entry", hours: 100) }
    let!(:reworked) { finding("k2", "Supplier set-up", hours: 50) }
    let!(:dropped) { finding("k3", "Statement checks", hours: 20) }
    let(:previous) do
      create(:report, company: company, version: 1, report_snapshot: { "findings" => Findings::ForReport.call(company: company) })
    end

    it "lists findings added, updated and superseded, and departments newly covered" do
      previous
      reworked.update!(consultant_effort: {}, annual_hours_min: 80, annual_hours_max: 90)
      dropped.update!(status: "merged", merged_into: kept)
      added = finding("k4", "Stock counts", department: "warehouse", hours: 40)

      delta = described_class.call(company: company, previous_report: previous)
      changes = delta["findings"]

      expect(changes["added"].map { |f| f["id"] }).to eq([added.id])
      expect(changes["updated"].map { |f| [f["id"], f["change"]] }).to eq([[reworked.id, "hours 80–90, were 50"]])
      expect(changes["superseded"].map { |f| [f["id"], f["reason"]] }).to eq([[dropped.id, "merged into “Invoice entry”"]])
      expect(changes["new_departments"]).to eq(["warehouse"])
      expect(delta["summary"]).to eq("1 new finding, 1 updated finding, 1 superseded finding, and Warehouse newly covered since Report v1")
    end

    it "says nothing moved when the findings are unchanged" do
      delta = described_class.call(company: company, previous_report: previous)

      expect(delta["findings"].values).to all(be_empty)
      expect(delta["summary"]).to eq("No changes to the findings since Report v1")
    end

    it "counts a revised cause or direction as an update" do
      previous
      kept.update!(consultant_cause: "Invoices arrive as scans", consultant_direction: "Read invoices as they arrive")

      updated = described_class.call(company: company, previous_report: previous)["findings"]["updated"]

      expect(updated.map { |f| [f["id"], f["change"]] }).to eq([[kept.id, "cause or direction revised on review"]])
    end

    it "does not count a cause appearing for the first time in a version that had none" do
      old = Findings::ForReport.call(company: company)
      old["departments"].each { |d| d["roles"].each { |r| r["findings"].each { |f| f.except!(*described_class::DIRECTION_KEYS) } } }
      before = create(:report, company: company, version: 1, report_snapshot: { "findings" => old })
      kept.update!(consultant_cause: "Invoices arrive as scans")

      expect(described_class.call(company: company, previous_report: before)["findings"]["updated"]).to be_empty
    end
  end
end
