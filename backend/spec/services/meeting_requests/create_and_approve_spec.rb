# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingRequests::CreateService do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user) }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    allow(NotificationService).to receive(:notify)
    allow(NotificationService).to receive(:app_host).and_return("http://localhost:5173")
  end

  it "creates a pending admin meeting request" do
    meeting = described_class.call(
      reviewer: reviewer,
      company: company,
      purpose: "Clarify finance approval bottleneck",
      desired_roles: %w[finance_lead],
      duration_minutes: 30
    )

    expect(meeting).to be_pending_admin
    expect(meeting.purpose).to include("finance")
  end
end

RSpec.describe MeetingRequests::ApproveService do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user) }
  let(:admin) { create(:company_user, company: company, role: "company_admin") }
  let(:meeting) do
    MeetingRequest.create!(
      company: company,
      reviewer_user: reviewer,
      purpose: "Call with ops",
      status: "pending_admin"
    )
  end

  before do
    allow(NotificationService).to receive(:notify)
    allow(NotificationService).to receive(:app_host).and_return("http://localhost:5173")
  end

  it "approves a pending meeting request" do
    described_class.call(meeting_request: meeting, company_user: admin, admin_note: "Booked")
    expect(meeting.reload.status).to eq("approved")
    expect(meeting.approved_by_company_user).to eq(admin)
  end
end
