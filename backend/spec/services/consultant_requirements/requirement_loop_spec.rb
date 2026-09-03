# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant requirement loop", type: :job do
  include ActiveJob::TestHelper
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:consultant) { create(:consultant_user) }
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          state_snapshot: { "blackboard" => { "profile" => { "name" => "Layla" } } })
  end
  let(:package) do
    DiscoveryPackage.create!(
      conversation: conversation, employee: employee, company: company,
      version: 1, status: "ready", recommendation: "Automate matching."
    )
  end

  let(:client) { instance_double(Langgraph::Client) }

  before do
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(client).to receive(:draft_requirement_questions!).and_return(
      { "questions" => [{ "body" => "Which system holds the approval?", "rationale" => "Settles it" }],
        "generated_by" => "llm" }
    )
  end

  describe "stating a need" do
    it "records the statement immediately and drafts off the request path" do
      requirement = ConsultantRequirements::CreateService.call(
        package: package, consultant: consultant,
        statement: "I need to know which system is the system of record for approvals."
      )

      expect(requirement.statement).to include("system of record")
      # Drafting is an LLM call that can take over a minute — the consultant gets
      # their requirement back now, and the questions when the job finishes.
      expect(requirement.status).to eq("open")
      expect(DraftRequirementQuestionsJob).to have_been_enqueued.with(requirement.id)
    end

    it "drafts a question from the statement, never using the consultant's words" do
      requirement = ConsultantRequirements::CreateService.call(
        package: package, consultant: consultant, statement: "Which system is the record?"
      )
      perform_enqueued_jobs

      requirement.reload
      expect(requirement.status).to eq("questions_drafted")
      expect(requirement.discovery_followup_questions.first.body)
        .to eq("Which system holds the approval?")
    end

    it "rejects an empty statement" do
      expect do
        ConsultantRequirements::CreateService.call(package: package, consultant: consultant, statement: "  ")
      end.to raise_error(ArgumentError)
    end

    it "keeps the requirement when drafting is unavailable, so the need is not lost" do
      allow(client).to receive(:draft_requirement_questions!)
        .and_raise(Langgraph::UnavailableError.new("down", retryable: true))

      requirement = ConsultantRequirements::CreateService.call(
        package: package, consultant: consultant, statement: "Need the approval owner."
      )
      perform_enqueued_jobs

      expect(requirement.reload).to be_persisted
      expect(requirement.status).to eq("open")
      expect(requirement.discovery_followup_questions).to be_empty
    end
  end

  describe "budgets" do
    def requirement_with_sent(count)
      requirement = ConsultantRequirement.create!(
        consultant_user: consultant, discovery_package: package, employee: employee,
        company: company, statement: "Need detail.", max_questions: 3
      )
      count.times do |i|
        package.discovery_followup_questions.create!(
          consultant_requirement: requirement, body: "q#{i}", status: "sent", queue_position: i + 1
        )
      end
      requirement
    end

    it "counts only questions actually put to the employee" do
      requirement = requirement_with_sent(1)
      package.discovery_followup_questions.create!(
        consultant_requirement: requirement, body: "a draft", status: "drafted", queue_position: 9
      )

      # A draft the consultant discarded must not spend the employee's allowance.
      expect(requirement.questions_asked).to eq(1)
      expect(requirement.budget_remaining).to eq(2)
    end

    it "stops drafting once the requirement's own budget is spent" do
      requirement = requirement_with_sent(3)

      expect(ConsultantRequirements::DraftQuestionsService.call(requirement: requirement)).to eq([])
      expect(client).not_to have_received(:draft_requirement_questions!)
    end

    it "stops drafting once the employee's package budget is spent, across requirements" do
      # This is the cap that protects the employee: three requirements each spending
      # three questions would be nine questions to one person.
      company.update!(settings: company.settings.merge("consultant_followup_max_per_package" => 2))
      requirement_with_sent(2)

      fresh = ConsultantRequirement.create!(
        consultant_user: consultant, discovery_package: package, employee: employee,
        company: company, statement: "Something else.", max_questions: 3
      )

      expect(ConsultantRequirements::DraftQuestionsService.call(requirement: fresh)).to eq([])
    end

    it "never drafts more than the remaining package allowance" do
      company.update!(settings: company.settings.merge("consultant_followup_max_per_package" => 3))
      requirement_with_sent(2)

      fresh = ConsultantRequirement.create!(
        consultant_user: consultant, discovery_package: package, employee: employee,
        company: company, statement: "One more thing.", max_questions: 3
      )
      ConsultantRequirements::DraftQuestionsService.call(requirement: fresh)

      expect(client).to have_received(:draft_requirement_questions!)
        .with(hash_including(max_questions: 1))
    end

    it "resolves the caps company setting -> ENV -> default" do
      expect(Discovery::FollowupLimits.max_per_package(company)).to eq(6)

      original = ENV["CONSULTANT_FOLLOWUP_MAX_PER_PACKAGE"]
      ENV["CONSULTANT_FOLLOWUP_MAX_PER_PACKAGE"] = "4"
      expect(Discovery::FollowupLimits.max_per_package(company)).to eq(4)

      company.update!(settings: company.settings.merge("consultant_followup_max_per_package" => 9))
      expect(Discovery::FollowupLimits.max_per_package(company.reload)).to eq(9)
    ensure
      ENV["CONSULTANT_FOLLOWUP_MAX_PER_PACKAGE"] = original
    end
  end

  describe "recording an answer" do
    let(:requirement) do
      ConsultantRequirement.create!(
        consultant_user: consultant, discovery_package: package, employee: employee,
        company: company, statement: "Which system is the record?", max_questions: 3,
        status: "questions_drafted"
      )
    end
    let(:question) do
      package.discovery_followup_questions.create!(
        consultant_requirement: requirement, body: "Which system holds the approval?",
        status: "sent", queue_position: 1
      )
    end
    let(:answer) do
      create(:message, conversation: conversation, direction: "inbound",
                       body: "SAP is the record.", track: "consultant_followup")
    end

    it "satisfies the requirement when the agent judges it settled" do
      allow(client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => true, "missing_aspects" => [] })

      ConsultantRequirements::RecordAnswerService.call(question: question, message: answer)

      expect(question.reload.status).to eq("answered")
      expect(question.answered_message).to eq(answer)
      expect(requirement.reload).to be_satisfied
      expect(requirement.satisfaction_basis).to eq("agent_judged")
    end

    it "records what is still missing and drafts again when not satisfied" do
      allow(client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => false, "missing_aspects" => ["Who approves it"] })
      # The redraft must ask something NEW. The default stub returns the same body as
      # the question already sent, and re-persisting that gave the consultant the
      # same question twice in their queue.
      allow(client).to receive(:draft_requirement_questions!)
        .and_return({ "questions" => [{ "body" => "Who approves a mismatched PI?" }] })

      ConsultantRequirements::RecordAnswerService.call(question: question, message: answer)
      perform_enqueued_jobs

      expect(requirement.reload.status).to eq("partially_satisfied")
      expect(requirement.missing_aspects).to eq(["Who approves it"])
      expect(requirement.discovery_followup_questions.pluck(:body))
        .to contain_exactly("Which system holds the approval?", "Who approves a mismatched PI?")
    end

    it "does not re-ask a question the employee has already been sent" do
      allow(client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => false, "missing_aspects" => ["Who approves it"] })
      # Default stub returns the same body as the sent question.
      ConsultantRequirements::RecordAnswerService.call(question: question, message: answer)
      perform_enqueued_jobs

      expect(requirement.reload.discovery_followup_questions.count).to eq(1)
    end

    it "leaves the requirement open for the consultant when evaluation is unavailable" do
      allow(client).to receive(:evaluate_requirement!)
        .and_raise(Langgraph::UnavailableError.new("down", retryable: true))

      ConsultantRequirements::RecordAnswerService.call(question: question, message: answer)

      # The answer is still attributed — that is the part that must not be lost.
      expect(question.reload.status).to eq("answered")
      expect(requirement.reload.status).to eq("partially_satisfied")
      expect(requirement.missing_aspects.first).to match(/could not be assessed/i)
    end

    it "never raises on the inbound path" do
      allow(client).to receive(:evaluate_requirement!).and_raise(StandardError, "boom")

      expect do
        ConsultantRequirements::RecordAnswerService.call(question: question, message: answer)
      end.not_to raise_error
      expect(question.reload.status).to eq("answered")
    end

    it "stops asking when an unsatisfiable requirement exhausts its budget" do
      allow(client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => false, "missing_aspects" => ["Still vague"] })
      requirement.update!(max_questions: 1)

      ConsultantRequirements::RecordAnswerService.call(question: question, message: answer)
      perform_enqueued_jobs

      # One sent question, budget of one: no further draft, so the employee is not
      # asked forever about a need that cannot be settled.
      expect(requirement.reload.discovery_followup_questions.count).to eq(1)
    end
  end

  describe "sending a question" do
    let(:question) do
      package.discovery_followup_questions.create!(body: "Which system?", status: "drafted", queue_position: 1)
    end

    before do
      allow(ConsultantFollowup::SendService).to receive(:call).and_return(
        { request: instance_double(ConsultantInfoRequest, id: 42), message: create(:message, conversation: conversation) }
      )
    end

    it "refuses once the employee's package allowance is spent" do
      company.update!(settings: company.settings.merge("consultant_followup_max_per_package" => 1))
      package.discovery_followup_questions.create!(body: "already asked", status: "sent", queue_position: 9)

      expect do
        ConsultantRequirements::SendQuestionService.call(question: question, consultant: consultant)
      end.to raise_error(ConsultantRequirements::SendQuestionService::BudgetExhausted)
    end

    it "refuses to send the same question twice" do
      question.update!(status: "sent")

      expect do
        ConsultantRequirements::SendQuestionService.call(question: question, consultant: consultant)
      end.to raise_error(ArgumentError, /already sent/)
    end
  end
end
