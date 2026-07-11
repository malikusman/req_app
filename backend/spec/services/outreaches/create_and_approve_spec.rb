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
