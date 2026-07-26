# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::FinalizeConversationService do
  let(:company) { create(:company, completed_count: 0, conversation_count: 0) }
  let(:employee) { create(:employee, company: company, participation_status: "started", department: "finance") }
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "discovery", question_count: 10)
  end

  it "marks the conversation and employee completed and enqueues aggregation jobs" do
    expect do
      described_class.call(conversation: conversation, employee: employee)
    end.to have_enqueued_job(AggregateIntelligenceJob).with(company.id)
      .and have_enqueued_job(MemoryPromotionJob).with(conversation.id)

    conversation.reload
    employee.reload
    expect(conversation.status).to eq("completed")
    expect(conversation.state_snapshot["finalized_at"]).to be_present
    expect(employee.participation_status).to eq("completed")
    expect(company.reload.completed_count).to eq(1)
  end

  it "re-enqueues aggregation after an addendum without double-counting completed_count" do
    described_class.call(conversation: conversation, employee: employee)
    company.reload
    expect(company.completed_count).to eq(1)

    conversation.update!(status: "discovery", question_count: 12)
    InsightTimelineEvent.where(event_type: "interview_completed").delete_all

    expect do
      described_class.call(conversation: conversation.reload, employee: employee.reload)
    end.to have_enqueued_job(AggregateIntelligenceJob)
      .and have_enqueued_job(MemoryPromotionJob)

    expect(company.reload.completed_count).to eq(1)
    expect(employee.reload.participation_status).to eq("completed")
    expect(conversation.reload.status).to eq("completed")
  end

  it "is a no-op when already completed" do
    conversation.update!(status: "completed")
    expect do
      described_class.call(conversation: conversation, employee: employee)
    end.not_to have_enqueued_job(MemoryPromotionJob)
  end
end
