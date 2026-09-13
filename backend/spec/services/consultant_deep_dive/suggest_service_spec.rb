# frozen_string_literal: true

require "rails_helper"

# Discovery stays deliberately light, so by review time there are things worth
# knowing that nobody thought to ask. This proposes them -- and it must cost the
# employee nothing until the consultant actually accepts one.
RSpec.describe ConsultantDeepDive::SuggestService do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          state_snapshot: { "blackboard" => blackboard })
  end
  let(:blackboard) do
    {
      "profile" => { "name" => "Layla", "role_title" => "AP Accountant" },
      "dossier" => {
        "slots" => {
          "friction::Invoicing" => { "value" => "re-keying every invoice", "confidence" => 0.8 }
        }
      }
    }
  end
  let(:package) do
    DiscoveryPackage.create!(conversation: conversation, employee: employee, company: company,
                             version: 1, status: "ready", recommendation: "Automate the match.")
  end

  def stub_agent(payload)
    allow_any_instance_of(Langgraph::Client)
      .to receive(:suggest_deep_dive_questions!).and_return(payload)
  end

  it "returns the agent's suggestions with their reasons" do
    stub_agent(
      "suggestions" => [
        { "body" => "How many invoices land in a week?", "rationale" => "Sizes the re-keying.",
          "kind" => "scale" }
      ],
      "generated_by" => "llm"
    )

    result = described_class.call(package: package)

    expect(result[:suggestions].first[:body]).to eq("How many invoices land in a week?")
    expect(result[:suggestions].first[:rationale]).to eq("Sizes the re-keying.")
    expect(result[:generated_by]).to eq("llm")
  end

  # A suggestion without a reason is just a question, and the consultant has no way
  # to judge whether it is worth one of the employee's few remaining answers.
  it "drops a suggestion that carries no reason" do
    stub_agent(
      "suggestions" => [
        { "body" => "How many?", "rationale" => "" },
        { "body" => "How long?", "rationale" => "Puts a time on it." }
      ],
      "generated_by" => "llm"
    )

    expect(described_class.call(package: package)[:suggestions].map { |s| s[:body] }).to eq(["How long?"])
  end

  # Nothing is persisted and no budget is spent, which is what makes it safe to
  # suggest generously -- the employee is only ever asked once a consultant accepts.
  it "persists nothing and spends no budget" do
    stub_agent("suggestions" => [{ "body" => "How long?", "rationale" => "Times it." }], "generated_by" => "llm")
    before = Discovery::FollowupLimits.package_budget_remaining(package)

    expect { described_class.call(package: package) }.to change(ConsultantRequirement, :count).by(0)
    expect { described_class.call(package: package) }.to change(DiscoveryFollowupQuestion, :count).by(0)
    expect(Discovery::FollowupLimits.package_budget_remaining(package)).to eq(before)
  end

  it "passes the dossier through, so the agent can see what was never costed" do
    expect_any_instance_of(Langgraph::Client).to receive(:suggest_deep_dive_questions!)
      .with(hash_including(dossier: hash_including("slots"))).and_return({ "suggestions" => [] })

    described_class.call(package: package)
  end

  it "never proposes more than the employee could actually be asked" do
    allow(Discovery::FollowupLimits).to receive(:package_budget_remaining).and_return(2)
    expect_any_instance_of(Langgraph::Client).to receive(:suggest_deep_dive_questions!)
      .with(hash_including(max_suggestions: 2)).and_return({ "suggestions" => [] })

    described_class.call(package: package)
  end

  it "suggests nothing once the package budget is spent" do
    allow(Discovery::FollowupLimits).to receive(:package_budget_remaining).and_return(0)
    expect_any_instance_of(Langgraph::Client).not_to receive(:suggest_deep_dive_questions!)

    result = described_class.call(package: package)

    expect(result[:suggestions]).to be_empty
    expect(result[:fallback_reason]).to eq("no_budget")
  end

  # A review that opens without suggestions is degraded; one that 500s is broken.
  it "degrades rather than raising when the agent is unavailable" do
    allow_any_instance_of(Langgraph::Client).to receive(:suggest_deep_dive_questions!)
      .and_raise(Langgraph::UnavailableError.new("down", retryable: true))

    result = described_class.call(package: package)

    expect(result[:suggestions]).to be_empty
    expect(result[:fallback_reason]).to eq("agent_unavailable")
  end

  it "does not re-ask something already put to this employee" do
    package.discovery_followup_questions.create!(body: "How long does it take?", status: "sent",
                                                 queue_position: 1)
    expect_any_instance_of(Langgraph::Client).to receive(:suggest_deep_dive_questions!)
      .with(hash_including(already_asked: ["How long does it take?"])).and_return({ "suggestions" => [] })

    described_class.call(package: package)
  end
end
