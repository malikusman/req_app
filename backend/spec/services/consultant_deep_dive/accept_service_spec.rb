# frozen_string_literal: true

require "rails_helper"

# Accepting is the moment a suggestion stops being free: it becomes an ordinary
# requirement, spends the employee's budget, and goes out under the consultant's
# name. Everything downstream must be unable to tell it apart from one a
# consultant typed by hand.
RSpec.describe ConsultantDeepDive::AcceptService do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          state_snapshot: { "blackboard" => {} })
  end
  let(:package) do
    DiscoveryPackage.create!(conversation: conversation, employee: employee, company: company,
                             version: 1, status: "ready", recommendation: "Automate the match.")
  end
  let(:body) { "Roughly how long does the re-keying take you in a week?" }
  let(:rationale) { "They described re-keying but never put a time to it." }

  def accept(**overrides)
    described_class.call(
      **{ package: package, consultant: consultant, body: body, rationale: rationale }.merge(overrides)
    )
  end

  it "creates a requirement owned by the consultant who accepted it" do
    requirement = accept[:requirement]

    expect(requirement.consultant_user).to eq(consultant)
    expect(requirement.employee).to eq(employee)
    expect(requirement.discovery_package).to eq(package)
  end

  # The rationale IS the need. It is what the satisfaction judge reads later to
  # decide whether the reply settled anything, so "they never put a time to it"
  # is worth far more there than the question text repeated back.
  it "records the reason as the requirement's statement" do
    expect(accept[:requirement].statement).to eq(rationale)
  end

  it "falls back to the question itself when no reason came with it" do
    expect(accept(rationale: "")[:requirement].statement).to eq(body)
  end

  # The consultant approved these words. Re-drafting would silently replace them
  # with the model's and charge a second call for the privilege.
  it "keeps the approved wording instead of re-drafting it" do
    result = accept

    expect(result[:question].body).to eq(body)
    expect(result[:requirement].status).to eq("questions_drafted")
    expect(result[:question].status).to eq("drafted")
  end

  it "queues behind questions already waiting for this employee" do
    package.discovery_followup_questions.create!(body: "Earlier one", status: "sent", queue_position: 4)

    expect(accept[:question].queue_position).to eq(5)
  end

  it "gives the question the same per-requirement budget as any other" do
    expect(accept[:requirement].max_questions)
      .to eq(Discovery::FollowupLimits.max_per_requirement(company))
  end

  # The package cap is the employee's protection from being interviewed twice.
  # A suggested question is not exempt from it just because the agent proposed it.
  it "refuses once the package budget is spent" do
    allow(Discovery::FollowupLimits).to receive(:package_budget_remaining).and_return(0)

    expect { accept }.to raise_error(described_class::BudgetExhausted)
    expect(ConsultantRequirement.count).to eq(0)
  end

  it "refuses an empty question" do
    expect { accept(body: "  ") }.to raise_error(ArgumentError)
  end

  # Half of this pair is useless: a requirement with no question never reaches the
  # employee, a question with no requirement is never judged or attributed.
  it "writes both records or neither" do
    allow_any_instance_of(DiscoveryPackage).to receive(:discovery_followup_questions)
      .and_raise(ActiveRecord::RecordInvalid.new(DiscoveryFollowupQuestion.new))

    expect { accept }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ConsultantRequirement.count).to eq(0)
  end
end
