# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Conversations", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }
  let(:company) { create(:company, :onboarded) }
  let!(:employee) { create(:employee, company: company) }
  let!(:conversation) { create(:conversation, employee: employee, company: company) }
  let!(:discovery_message) { create(:message, conversation: conversation, body: "Discovery reply", reviewer_followup: false) }
  let!(:followup_message) { create(:message, conversation: conversation, body: "Hidden followup", reviewer_followup: true) }

  describe "GET /api/v1/platform/companies/:company_id/conversations" do
    it "lists conversations for the company" do
      get "/api/v1/platform/companies/#{company.id}/conversations", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["conversations"].length).to eq(1)
      expect(body["conversations"].first["employee_name"]).to eq(employee.display_name)
    end

    it "returns unauthorized without token" do
      get "/api/v1/platform/companies/#{company.id}/conversations"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/platform/companies/:company_id/conversations/:id" do
    it "returns conversation messages excluding reviewer followups" do
      get "/api/v1/platform/companies/#{company.id}/conversations/#{conversation.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      bodies = body["messages"].map { |m| m["body"] }
      expect(bodies).to include("Discovery reply")
      expect(bodies).not_to include("Hidden followup")
    end

    it "returns not found when conversation belongs to another company" do
      other_company = create(:company, :onboarded)
      other_employee = create(:employee, company: other_company)
      other_conversation = create(:conversation, employee: other_employee, company: other_company)

      get "/api/v1/platform/companies/#{company.id}/conversations/#{other_conversation.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
