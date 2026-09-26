# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::BuildFromConversation do
  let(:company) { create(:company, :onboarded) }
  let(:employee) do
    create(:employee, company: company, department: "procurement", role_title: "Procurement Officer",
                      participation_status: "completed")
  end
  let(:dossier) do
    {
      "slots" => {
        "how_it_works::supplier price updates" => { "value" => "Re-keys supplier sheets into NAV", "confidence" => 0.8, "turn" => 3 },
        "friction::supplier price updates" => { "value" => "Codes mismatch, wrong prices reach customers", "confidence" => 0.9, "turn" => 4 },
        "friction_cost::supplier price updates" => {
          "value" => "forty minutes to an hour every morning", "confidence" => 0.8, "turn" => 5,
          "effort" => {
            "frequency" => { "as_said" => "every morning", "min" => 1, "max" => 1, "unit" => "per_day" },
            "duration" => { "as_said" => "forty minutes to an hour", "min" => 40, "max" => 60, "unit" => "minutes" },
            "effort_type" => "active"
          }
        },
        "how_it_works::purchase orders" => { "value" => "Raises POs in NAV", "confidence" => 0.8, "turn" => 6 },
        # No friction captured for purchase orders: no finding.
        "ai_current_usage" => { "value" => "ChatGPT for emails", "confidence" => 0.8, "turn" => 7 }
      },
      "parked" => []
    }
  end
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          state_snapshot: { "blackboard" => {
                            "role_areas" => [{ "name" => "supplier price updates" }, { "name" => "purchase orders" }],
                            "dossier" => dossier
                          } })
  end

  it "builds one finding per area that has a friction, with hours worked out in code" do
    findings = described_class.call(conversation: conversation)

    expect(findings.size).to eq(1)
    finding = findings.first
    expect(finding).to have_attributes(
      department: "procurement", role_title: "Procurement Officer", area: "supplier price updates",
      what_happens_now: "Re-keys supplier sheets into NAV",
      friction: "Codes mismatch, wrong prices reach customers",
      frequency_unit: "per_day", duration_unit: "minutes", effort_type: "active",
      annual_hours_min: 160, annual_hours_max: 240,
      basis: "discovery", confidence: "high", status: "draft"
    )
    expect(finding.evidence).to include("conversation_id" => conversation.id,
                                        "slots" => { "friction" => 4, "how_it_works" => 3, "friction_cost" => 5 })
  end

  it "flags a role only one person holds" do
    finding = described_class.call(conversation: conversation).first
    expect(finding.single_occupant_role).to be(true)

    create(:employee, company: company, role_title: "procurement officer ")
    expect(described_class.call(conversation: conversation).first.single_occupant_role).to be(false)
  end

  it "keeps what was said when no numbers were given, and reports no hours" do
    dossier["slots"]["friction_cost::supplier price updates"]["effort"] = {
      "frequency" => { "as_said" => "it depends on the season" }, "duration" => nil, "effort_type" => "unknown"
    }
    finding = described_class.call(conversation: conversation).first  # built after the edit, so it sees it
    expect(finding.frequency_as_said).to eq("it depends on the season")
    expect(finding.hours?).to be(false)
    expect(finding.confidence).to eq("medium")
  end

  it "is idempotent and never overwrites a consultant's decision" do
    first = described_class.call(conversation: conversation).first
    first.update!(status: "approved")

    snapshot = conversation.state_snapshot.deep_dup
    snapshot["blackboard"]["dossier"]["slots"]["friction::supplier price updates"]["value"] =
      "Codes mismatch between supplier sheets and NAV"
    conversation.update!(state_snapshot: snapshot)
    again = described_class.call(conversation: conversation.reload).first

    expect(again.id).to eq(first.id)
    expect(again.friction).to eq("Codes mismatch between supplier sheets and NAV")
    expect(again.status).to eq("approved")
    expect(company.findings.count).to eq(1)
  end

  it "keeps what an unfinished interview captured, marked partial and low confidence" do
    conversation.update!(status: "abandoned")
    finding = described_class.call(conversation: conversation).first
    expect(finding).to have_attributes(basis: "discovery_partial", confidence: "low")
  end

  it "builds nothing from an interview still in progress" do
    conversation.update!(status: "discovery")
    expect(described_class.call(conversation: conversation)).to eq([])
  end
end
