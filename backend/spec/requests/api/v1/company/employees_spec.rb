# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Employees", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:company_user) { create(:company_user, company: company, role: "company_admin") }
  let(:headers) { auth_headers_for(company_user) }

  def csv_file(contents)
    tempfile = Tempfile.new(["employees", ".csv"])
    tempfile.write(contents)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "text/csv", original_filename: "employees.csv")
  end

  describe "POST /api/v1/company/employees" do
    it "creates an employee with email only invite" do
      post "/api/v1/company/employees",
           params: { email: "employee-#{SecureRandom.hex(4)}@example.com", display_name: "Email Employee" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("employee", "email")).to be_present
      expect(response.parsed_body.dig("employee", "phone_e164")).to be_nil
    end

    it "allows invite creation even when subscription is inactive" do
      company.subscription.update!(status: "churned")

      post "/api/v1/company/employees",
           params: { phone_e164: "+14155559999", display_name: "Pre-subscription Employee" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("employee", "id")).to be_present
    end
  end

  describe "POST /api/v1/company/employees/bulk_create" do
    it "creates employees from csv upload" do
      file = csv_file(<<~CSV)
        phone_e164,email,display_name,department
        +14155550111,,Person One,Ops
        ,person.two@example.com,Person Two,Finance
      CSV

      post "/api/v1/company/employees/bulk_create",
           params: { file: file },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch("employees").size).to eq(2)
      expect(response.parsed_body["batch_id"]).to be_present
    end

    it "allows bulk invites even when subscription is inactive" do
      company.subscription.update!(status: "churned")
      file = csv_file(<<~CSV)
        phone_e164,email,display_name,department
        +14155550112,,Person Three,Ops
      CSV

      post "/api/v1/company/employees/bulk_create",
           params: { file: file },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch("employees").size).to eq(1)
    end
  end
end
