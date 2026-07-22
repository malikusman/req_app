# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryPromotionJob do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) do
    create(:conversation, employee: employee, status: "completed", state_snapshot: {
             "blackboard" => {
               "shared_findings" => [
                 { "agent" => "domain_finance", "finding" => "Invoices wait 3 days for sign-off", "confidence" => 0.8, "turn" => 2 },
                 { "agent" => "technical", "finding" => "Low-signal note", "confidence" => 0.3, "turn" => 3 }
               ]
             }
           })
  end

  before do
    openai = instance_double(Openai::Client, configured?: true, embedding: Array.new(1536, 0.1))
    allow(Openai::Client).to receive(:new).and_return(openai)
  end

  it "promotes only findings above the confidence threshold" do
    described_class.perform_now(conversation.id)

    facts = company.company_memory_facts
    expect(facts.count).to eq(1)
    fact = facts.first
    expect(fact.content).to eq("Invoices wait 3 days for sign-off")
    expect(fact.source_agent).to eq("domain_finance")
    expect(fact.department).to eq("finance")
    expect(fact.employee).to eq(employee)
  end

  it "is idempotent across re-runs" do
    described_class.perform_now(conversation.id)
    described_class.perform_now(conversation.id)
    expect(company.company_memory_facts.count).to eq(1)
  end

  it "does nothing when the blackboard has no findings" do
    bare = create(:conversation, employee: employee, status: "completed")
    expect { described_class.perform_now(bare.id) }.not_to change(CompanyMemoryFact, :count)
  end

  it "skips promotion when OpenAI is not configured" do
    openai = instance_double(Openai::Client, configured?: false)
    allow(Openai::Client).to receive(:new).and_return(openai)

    expect { described_class.perform_now(conversation.id) }.not_to change(CompanyMemoryFact, :count)
  end

  it "skips promotion when embedding returns nil" do
    openai = instance_double(Openai::Client, configured?: true, embedding: nil)
    allow(Openai::Client).to receive(:new).and_return(openai)

    expect { described_class.perform_now(conversation.id) }.not_to change(CompanyMemoryFact, :count)
  end
end
