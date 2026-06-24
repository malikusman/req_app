# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendEmployeeNudgeJob, type: :job do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:company_user) { create(:company_user, company: company) }
  let(:employee) { create(:employee, company: company, participation_status: "started", last_nudged_at: nil) }

  def create_nudge(employee:, channel: "whatsapp_template")
    EmployeeNudge.create!(
      employee: employee,
      company_user: company_user,
      channel: channel,
      delivery_status: "queued",
      whatsapp_status: "queued",
      email_status: channel == "whatsapp_and_email" ? "queued" : "skipped",
      sent_at: Time.current
    )
  end

  it "delivers WhatsApp nudge and marks sent" do
    nudge = create_nudge(employee: employee)

    perform_enqueued_jobs do
      described_class.perform_later(nudge.id)
    end

    nudge.reload
    employee.reload
    expect(nudge.delivery_status).to eq("sent")
    expect(nudge.whatsapp_status).to eq("sent")
    expect(employee.last_nudged_at).to be_present
  end

  it "delivers WhatsApp and email when employee has email" do
    employee.update!(email: "employee@example.com")
    nudge = create_nudge(employee: employee, channel: "whatsapp_and_email")

    expect {
      described_class.perform_now(nudge.id)
    }.to change { ActionMailer::Base.deliveries.count }.by(1)

    nudge.reload
    expect(nudge.delivery_status).to eq("sent")
    expect(nudge.email_status).to eq("sent")
  end

  it "marks failed when both channels fail" do
    employee.update!(email: "employee@example.com")
    nudge = create_nudge(employee: employee, channel: "whatsapp_and_email")

    allow_any_instance_of(Whatsapp::MetaClient).to receive(:configured?).and_return(true)
    allow_any_instance_of(Whatsapp::MetaClient).to receive(:send_nudge_template)
      .and_raise(Whatsapp::MetaClient::ApiError, "API down")
    allow(EmployeeNudgeMailer).to receive_message_chain(:nudge_email, :deliver_now)
      .and_raise(StandardError, "SMTP error")

    described_class.perform_now(nudge.id)

    nudge.reload
    expect(nudge.delivery_status).to eq("failed")
    expect(nudge.error_message).to include("WhatsApp")
    expect(nudge.error_message).to include("Email")
    expect(employee.reload.last_nudged_at).to be_nil
  end
end
