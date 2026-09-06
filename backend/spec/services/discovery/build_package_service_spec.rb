# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::BuildPackageService do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) do
    create(
      :conversation,
      employee: employee,
      company: company,
      status: "completed",
      question_count: 7,
      state_snapshot: {
        "blackboard" => {
          "profile" => { "name" => "Layla", "role_title" => "AP Specialist" },
          "role_areas" => [{ "name" => "invoice processing" }],
          "dossier" => {
            "slots" => {
              "friction::invoice processing" => { "value" => "Manual copy-paste", "confidence" => 0.9 }
            },
            "parked" => [{ "note" => "a shadow spreadsheet", "turn" => 4 }]
          }
        }
      }
    )
  end

  let(:agent_payload) do
    {
      "recommendation" => "Start with invoice matching.",
      "recommendation_rationale" => "Clearest friction.",
      "confidence" => 0.8,
      "generated_by" => "llm",
      "issues" => [
        { "title" => "Copy-paste", "body" => "Manual copy-paste between systems", "impact" => "high" }
      ],
      "solutions" => [
        { "title" => "Auto-match", "body" => "Match POs automatically", "impact" => "high",
          "addresses" => "Copy-paste" }
      ],
      "followup_questions" => [
        { "body" => "Tell me about the spreadsheet?", "rationale" => "Parked earlier",
          "from_parked" => "a shadow spreadsheet" }
      ]
    }
  end

  before do
    allow_any_instance_of(Langgraph::Client)
      .to receive(:build_discovery_package!).and_return(agent_payload)
  end

  it "builds a ready package with issues, solutions and follow-ups" do
    package = described_class.call(conversation: conversation)

    expect(package.status).to eq("ready")
    expect(package.version).to eq(1)
    expect(package.recommendation).to eq("Start with invoice matching.")
    expect(package.generated_by).to eq("llm")
    expect(package.issues.count).to eq(1)
    expect(package.solutions.count).to eq(1)
    expect(package.discovery_followup_questions.count).to eq(1)
  end

  it "links a solution to the issue it addresses" do
    package = described_class.call(conversation: conversation)

    expect(package.solutions.first.linked_item).to eq(package.issues.first)
  end

  it "queues the first follow-up as the next one to go out" do
    package = described_class.call(conversation: conversation)

    expect(package.next_followup.queue_position).to eq(1)
    expect(package.next_followup.from_parked_aside?).to be(true)
  end

  it "keeps the verbatim agent output for audit" do
    package = described_class.call(conversation: conversation)

    # The consultant will edit the rows; the original must remain inspectable.
    expect(package.agent_payload["recommendation"]).to eq("Start with invoice matching.")
  end

  it "skips items with no body rather than creating empty rows" do
    agent_payload["issues"] << { "title" => "Empty", "body" => "" }
    package = described_class.call(conversation: conversation)

    expect(package.issues.count).to eq(1)
  end

  describe "on an addendum re-run" do
    it "mints a new version and supersedes the previous one" do
      first = described_class.call(conversation: conversation)
      second = described_class.call(conversation: conversation)

      expect(first.reload.status).to eq("superseded")
      expect(second.version).to eq(2)
      expect(DiscoveryPackage.current.where(conversation: conversation)).to contain_exactly(second)
    end

    it "carries a consultant's own items forward" do
      first = described_class.call(conversation: conversation)
      first.discovery_package_items.create!(
        kind: "issue", body: "Something the consultant spotted", origin: "consultant", status: "accepted"
      )

      second = described_class.call(conversation: conversation)

      carried = second.discovery_package_items.where(origin: "consultant")
      expect(carried.map(&:body)).to eq(["Something the consultant spotted"])
    end

    it "re-applies a consultant's rejection of an agent item" do
      first = described_class.call(conversation: conversation)
      first.issues.first.update!(status: "rejected")

      second = described_class.call(conversation: conversation)

      # Without this the agent's rejected issue comes back on every addendum and the
      # consultant has to reject it again.
      expect(second.issues.first.status).to eq("rejected")
    end
  end

  describe "when the agent is unreachable" do
    it "marks the package failed and re-raises for the job to log" do
      allow_any_instance_of(Langgraph::Client)
        .to receive(:build_discovery_package!)
        .and_raise(Langgraph::UnavailableError.new("down", retryable: true))

      expect { described_class.call(conversation: conversation) }.to raise_error(Langgraph::UnavailableError)
      expect(DiscoveryPackage.last.status).to eq("failed")
      expect(DiscoveryPackage.last.error_message).to eq("down")
    end
  end
end
