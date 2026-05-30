# frozen_string_literal: true

require "rails_helper"

RSpec.describe InviteEmployeeService do
  describe ".call" do
    let(:company) { create(:company) }
    let(:invited_by) { create(:company_user, company: company) }

    it "creates employee, company join code, and invitation without personal access codes" do
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
        expect(result[:company_join_code]).to match(/\A[A-Z0-9]{5}\z/)
        expect(result[:invitation]).to be_persisted
        expect(result[:employee].employee_access_codes.count).to eq(0)
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

    it "enqueues email job when email is present" do
      expect {
        described_class.call(
          company: company,
          email: "alex@example.com",
          invited_by: invited_by,
          send_whatsapp: false,
          send_email: true
        )
      }.to have_enqueued_job(SendEmployeeEmailInvitationJob)
    end

    it "increments company invited_count" do
      expect {
        described_class.call(company: company, phone_e164: "+15551112222", send_whatsapp: false)
      }.to change { company.reload.invited_count }.by(1)
    end
  end
end
