# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarkAbandonedConversationsJob, type: :job do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }

  it "marks inactive conversations as abandoned" do
    conversation = create(
      :conversation,
      employee: employee,
      company: company,
      status: "discovery",
      last_activity_at: 4.days.ago
    )

    described_class.perform_now

    expect(conversation.reload.status).to eq("abandoned")
    expect(conversation.abandon_reason).to eq("inactivity_timeout")
  end

  it "leaves recently active conversations unchanged" do
    conversation = create(
      :conversation,
      employee: employee,
      company: company,
      status: "discovery",
      last_activity_at: 1.hour.ago
    )

    described_class.perform_now

    expect(conversation.reload.status).to eq("discovery")
  end
end
