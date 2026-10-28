# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::DraftCauseAndDirection do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let!(:finding) do
    company.findings.create!(employee: employee, source_key: "k1", area: "price updates", title: "Supplier price updates",
                             role_title: "Procurement Officer", department: "procurement",
                             friction: "Each supplier's sheet has a different layout", status: "draft")
  end
  let(:client) { instance_double(Openai::Client, configured?: true) }

  before do
    ENV["AI_REPORT_NARRATIVE"] = "true" # switched off suite-wide by spec/support/report_narrative.rb
    allow(Openai::Client).to receive(:new).and_return(client)
  end

  def reply(**fields)
    allow(client).to receive(:finding_causes).and_return(
      "findings" => [{ "id" => finding.id, "cause" => "Supplier sheets come in different layouts with no import route.",
                       "cause_stated" => true, "intervention_type" => "integration_data_fix",
                       "direction" => "Bring supplier price sheets into the ERP directly, flagging only exceptions." }.merge(fields)]
    )
  end

  it "keeps a draft that passes, and records what it was drafted from" do
    reply
    described_class.call(findings: [finding])

    finding.reload
    expect(finding.cause).to start_with("Supplier sheets come in different layouts")
    expect(finding.cause_stated).to be(true)
    expect(finding.intervention_type).to eq("integration_data_fix")
    expect(finding.direction).to start_with("Bring supplier price sheets")
    expect(finding.draft_stale?).to be(false)
  end

  it "drops a field with a figure, build detail or an unknown kind of change, and keeps the rest" do
    reply("cause" => "It takes 45 minutes every morning.", "intervention_type" => "blockchain",
          "direction" => "Build a bot; the implementation plan runs in sprints.")
    described_class.call(findings: [finding])

    finding.reload
    expect([finding.cause, finding.intervention_type, finding.direction]).to all(be_nil)
    expect(finding.cause_stated).to be(false)
    expect(finding.draft_digest).to be_present
  end

  it "drops a direction that names a catalogue product" do
    SolutionCatalogEntry.create!(name: "Rossum", category: "automation", active: true, first_party: false)
    reply("direction" => "Read supplier sheets with Rossum and flag only exceptions.")
    described_class.call(findings: [finding])
    expect(finding.reload.direction).to be_nil
  end

  it "redrafts only when the wording it was drafted from changes" do
    reply
    described_class.call(findings: [finding])
    described_class.call(findings: [finding.reload])
    expect(client).to have_received(:finding_causes).once

    finding.update!(consultant_friction: "Price sheets are retyped line by line")
    described_class.call(findings: [finding])
    expect(client).to have_received(:finding_causes).twice
  end

  it "leaves findings as they were when the model fails" do
    allow(client).to receive(:finding_causes).and_raise(StandardError, "timeout")
    expect(described_class.call(findings: [finding])).to eq([])
    expect(finding.reload.draft_digest).to be_nil
  end
end
