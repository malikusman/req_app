# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Employees nudge", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:company_user) { create(:company_user, company: company) }
  let(:employee) { create(:employee, company: company, participation_status: "started") }
  let(:headers) { auth_headers_for(company_user) }

  describe "POST /api/v1/company/employees/:id/nudge" do
    it "queues a nudge for started employees" do
      expect {
        post "/api/v1/company/employees/#{employee.id}/nudge", headers: headers
      }.to have_enqueued_job(SendEmployeeNudgeJob)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body["message"]).to eq("Nudge queued")
      expect(body["nudge"]["delivery_status"]).to eq("queued")
    end

    it "returns 422 when employee has not started" do
      employee.update!(participation_status: "invited")

      post "/api/v1/company/employees/#{employee.id}/nudge", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("not started")
    end

    it "returns 429 during cooldown" do
      employee.update!(last_nudged_at: 1.hour.ago)

      post "/api/v1/company/employees/#{employee.id}/nudge", headers: headers

      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["retry_after_hours"]).to be > 0
    end

    it "uses whatsapp_and_email channel when employee has email" do
      employee.update!(email: "employee@example.com")

      post "/api/v1/company/employees/#{employee.id}/nudge", headers: headers

      expect(response).to have_http_status(:ok)
      nudge = EmployeeNudge.order(:id).last
      expect(nudge.channel).to eq("whatsapp_and_email")
    end
  end

  describe "POST /api/v1/company/employees" do
    it "accepts optional email on invite" do
      post "/api/v1/company/employees",
           params: { phone_e164: "+14155559999", display_name: "Alex", email: "Alex@Example.com" },
           headers: headers

      expect(response).to have_http_status(:created)
      employee = Employee.find_by(phone_e164: "+14155559999")
      expect(employee.email).to eq("alex@example.com")
    end
  end
end
