# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendEmployeeNudgeJob, type: :job do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:company_user) { create(:company_user, company: company) }
  let(:employee) { create(:employee, company: company, participation_status: "started", last_nudged_at: nil) }

  it "sends a nudge and records employee_nudge" do
    perform_enqueued_jobs do
      described_class.perform_later(employee.id, company_user.id)
    end

    employee.reload
    expect(employee.employee_nudges.count).to eq(1)
    expect(employee.last_nudged_at).to be_present
  end

  it "skips duplicate nudges within cooldown" do
    create(:employee_nudge, employee: employee, company_user: company_user, sent_at: 1.hour.ago)

    expect {
      described_class.perform_now(employee.id, company_user.id)
    }.not_to change(EmployeeNudge, :count)
  end
end
