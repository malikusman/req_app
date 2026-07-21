# frozen_string_literal: true

require "rails_helper"

RSpec.describe Outreaches::CreateService do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user) }
  let(:employee) { create(:employee, company: company) }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
  end

  it "creates an outreach pending admin approval without sending" do
    outreach = described_class.call(
      reviewer: reviewer,
      company: company,
      employee_id: employee.id,
      body: "Can you clarify the SAP handoff?",
      purpose: "clarification",
      channel: "whatsapp"
    )

    expect(outreach).to be_pending_admin
    expect(outreach.status).to eq("pending_admin_approval")
    expect(outreach.body).to include("SAP")
  end

  it "sends company_admin portal outreaches immediately without approval" do
    admin = create(:company_user, company: company, role: "company_admin", status: "active")

    outreach = described_class.call(
      reviewer: reviewer,
      company: company,
      recipient_type: "company_admin",
      recipient_id: admin.id,
      body: "Omar — can you confirm demurrage accrual timing?",
      purpose: "clarification",
      channel: "whatsapp"
    )

    expect(outreach.status).to eq("sent")
    expect(outreach.channel).to eq("portal")
    expect(outreach.recipient_type).to eq("company_admin")
    expect(outreach.recipient_id).to eq(admin.id)
    expect(outreach.employee_id).to be_nil
    expect(outreach.sent_at).to be_present
  end

  it "defaults company_admin recipient to the first active admin" do
    admin = create(:company_user, company: company, role: "company_admin", status: "active")

    outreach = described_class.call(
      reviewer: reviewer,
      company: company,
      recipient_type: "company_admin",
      body: "Question for the company admin",
      purpose: "clarification"
    )

    expect(outreach.recipient_id).to eq(admin.id)
    expect(outreach.status).to eq("sent")
  end

  it "records an admin answer closing the company_admin clarification" do
    admin = create(:company_user, company: company, role: "company_admin", status: "active")
    outreach = described_class.call(
      reviewer: reviewer,
      company: company,
      recipient_type: "company_admin",
      body: "Confirm Excel exception tab usage.",
      purpose: "clarification"
    )

    reply = Outreaches::RecordReplyService.call(
      outreach: outreach,
      body: "Yes — AP parks exceptions in Excel until SAP release.",
      channel: "portal",
      company_user: admin
    )
    outreach.update!(status: "closed")

    expect(reply.body).to include("Excel")
    expect(outreach.reload.status).to eq("closed")
    expect(outreach.reviewer_outreach_replies.count).to eq(1)
  end
end

RSpec.describe Outreaches::ApproveService do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user) }
  let(:admin) { create(:company_user, company: company, role: "company_admin") }
  let(:employee) { create(:employee, company: company) }
  let(:outreach) do
    ReviewerOutreach.create!(
      company: company,
      reviewer_user: reviewer,
      employee: employee,
      recipient_type: "employee",
      recipient_id: employee.id,
      purpose: "clarification",
      channel: "email",
      status: "pending_admin_approval",
      body: "Please clarify"
    )
  end

  it "approves and enqueues delivery" do
    expect {
      described_class.call(outreach: outreach, admin: admin, note: "ok")
    }.to have_enqueued_job(DeliverOutreachJob)

    expect(outreach.reload.status).to eq("approved")
    expect(outreach.approved_by_company_user).to eq(admin)
  end
end
