# frozen_string_literal: true

require "rails_helper"

RSpec.describe InviteEmployeeService do
  describe ".call" do
    let(:company) { create(:company) }
    let(:invited_by) { create(:company_user, company: company) }

    it "creates employee and invitation without access codes" do
      expect {
        result = described_class.call(
          company: company,
          phone_e164: "+15551234567",
          display_name: "Alex",
          department: "finance",
          invited_by: invited_by,
          send_whatsapp: false
        )

        expect(result[:employee]).to be_persisted
        expect(result[:employee].phone_e164).to eq("+15551234567")
        expect(result[:employee].participation_status).to eq("invited")
        expect(result[:employee].onboarding_step).to eq("awaiting_consent")
        expect(result[:access_code]).to be_nil
        expect(result[:invitation]).to be_persisted
      }.to change(Employee, :count).by(1)
        .and change(EmployeeInvitation, :count).by(1)
    end

    it "enqueues invitation job when send_whatsapp is true" do
      expect {
        described_class.call(
          company: company,
          phone_e164: "+15559876543",
          invited_by: invited_by,
          send_whatsapp: true
        )
      }.to have_enqueued_job(SendEmployeeInvitationJob)
    end

    it "increments company invited_count" do
      expect {
        described_class.call(company: company, phone_e164: "+15551112222", send_whatsapp: false)
      }.to change { company.reload.invited_count }.by(1)
    end

    it "issues web session and email when preferred_channel is web" do
      expect {
        result = described_class.call(
          company: company,
          phone_e164: "+15553334444",
          display_name: "Web User",
          email: "web@example.com",
          preferred_channel: "web",
          send_whatsapp: false
        )

        expect(result[:discover_url]).to include("/discover/")
        expect(result[:employee].preferred_channel).to eq("web")
      }.to change(EmployeeWebSession, :count).by(1)
        .and have_enqueued_job(ActionMailer::MailDeliveryJob)
    end
  end
end
