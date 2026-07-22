# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public company registrations", type: :request do
  let(:valid_params) do
    {
      company_name: "Northwind Logistics",
      admin_name: "Sam Admin",
      admin_email: "sam@northwind.test",
      role_title: "COO",
      notes: "Docs-first pilot"
    }
  end

  it "creates a pending company + pending admin and enqueues emails" do
    expect {
      post "/api/v1/public/company_registrations", params: valid_params
    }.to change(Company, :count).by(1)
      .and change(CompanyUser, :count).by(1)
      .and change(CompanyRegistration, :count).by(1)
      .and have_enqueued_mail(SignupMailer, :company_registration_received)
      .and have_enqueued_mail(SignupMailer, :company_registration_admin_notice)

    expect(response).to have_http_status(:created)
    company = Company.last
    user = CompanyUser.last
    expect(company.approval_status).to eq("pending_approval")
    expect(company.subscription).to be_nil
    expect(user.status).to eq("pending")
    expect(user.email).to eq("sam@northwind.test")
  end

  it "rejects duplicate emails" do
    create(:company_user, email: "sam@northwind.test")
    post "/api/v1/public/company_registrations", params: valid_params
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "silently drops honeypot submissions" do
    expect {
      post "/api/v1/public/company_registrations", params: valid_params.merge(website: "http://spam.test")
    }.not_to change(CompanyRegistration, :count)
    expect(response).to have_http_status(:created)
  end
end
