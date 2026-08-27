# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::OutreachReplyHandler do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, company: company, employee: employee) }
  let(:consultant) { create(:consultant_user) }
  let!(:outreach) do
    ConsultantOutreach.create!(
      company: company,
      employee: employee,
      conversation: conversation,
      consultant_user: consultant,
      recipient_type: "employee",
      recipient_id: employee.id,
      purpose: "clarification",
      channel: "whatsapp",
      status: "sent",
      sent_at: Time.current,
      body: "Need more detail on approvals"
    )
  end

  it "records a whatsapp reply against the open outreach" do
    handled = described_class.new(
      employee: employee,
      conversation: conversation,
      text: "Approvals take 3 days",
      external_id: "wamid.abc",
      client: instance_double(Whatsapp::MetaClient)
    ).handle

    expect(handled).to eq(true)
    expect(outreach.reload.status).to eq("replied")
    expect(outreach.consultant_outreach_replies.last.body).to eq("Approvals take 3 days")
    expect(conversation.messages.where(direction: "inbound").last.body).to eq("Approvals take 3 days")
  end

  it "returns false when no open whatsapp outreach exists" do
    outreach.update!(status: "closed")
    handled = described_class.new(
      employee: employee,
      conversation: conversation,
      text: "ignored",
      external_id: "wamid.xyz",
      client: instance_double(Whatsapp::MetaClient)
    ).handle

    expect(handled).to eq(false)
  end
end
