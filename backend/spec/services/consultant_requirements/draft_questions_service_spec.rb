# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsultantRequirements::DraftQuestionsService do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }
  let(:consultant) { create(:consultant_user) }
  let(:package) do
    DiscoveryPackage.create!(conversation: conversation, employee: employee, company: company,
                             version: 1, status: "ready", recommendation: "Automate the match.")
  end
  let(:requirement) do
    ConsultantRequirement.create!(consultant_user: consultant, discovery_package: package,
                                  employee: employee, company: company, max_questions: 3,
                                  statement: "I need to know who signs off on a PI.")
  end

  def stub_draft(questions)
    allow_any_instance_of(Langgraph::Client)
      .to receive(:draft_requirement_questions!)
      .and_return({ "questions" => questions })
  end

  it "persists drafted questions in queue order" do
    stub_draft([{ "body" => "Who approves a mismatched PI?", "rationale" => "settles sign-off" }])

    described_class.call(requirement: requirement)

    expect(package.discovery_followup_questions.pluck(:body)).to eq(["Who approves a mismatched PI?"])
  end

  describe "re-drafting for the same need" do
    it "does not duplicate a question already drafted" do
      stub_draft([{ "body" => "Who approves a mismatched PI?" }])

      described_class.call(requirement: requirement)
      described_class.call(requirement: requirement.reload)

      # Drafting legitimately runs again after a partial answer; without dedup the
      # consultant saw the same question repeated in their queue.
      expect(package.discovery_followup_questions.count).to eq(1)
    end

    it "ignores casing and whitespace when comparing" do
      stub_draft([{ "body" => "Who approves a mismatched PI?" }])
      described_class.call(requirement: requirement)

      stub_draft([{ "body" => "  who   APPROVES a mismatched PI?  " }])
      described_class.call(requirement: requirement.reload)

      expect(package.discovery_followup_questions.count).to eq(1)
    end

    it "still adds a genuinely new question" do
      stub_draft([{ "body" => "Who approves a mismatched PI?" }])
      described_class.call(requirement: requirement)

      stub_draft([{ "body" => "Can they hold the payment?" }])
      described_class.call(requirement: requirement.reload)

      expect(package.discovery_followup_questions.count).to eq(2)
    end
  end
end
