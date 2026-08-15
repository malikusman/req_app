# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::SetCompanyAdminPassword do
  let(:company) { create(:company, approval_status: "approved", approved_at: 1.day.ago) }

  it "sets the password and emails credentials to the first company admin" do
    admin = create(:company_user, company: company, email: "admin@example.com", role: "company_admin", status: "active", password: "old-password")

    expect {
      described_class.call(company: company, password: "new-password-1")
    }.to have_enqueued_mail(SignupMailer, :company_admin_credentials)

    expect(admin.reload.authenticate("new-password-1")).to eq(admin)
  end

  it "raises when there is no admin" do
    expect {
      described_class.call(company: company, password: "new-password-1")
    }.to raise_error(described_class::Error, /No company admin/)
  end

  it "raises when the password is too short" do
    create(:company_user, company: company, role: "company_admin", status: "active")

    expect {
      described_class.call(company: company, password: "short")
    }.to raise_error(described_class::Error, /at least 8/)
  end
end
