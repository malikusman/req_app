# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Conversations", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:company_user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(company_user) }
  let!(:employee) { create(:employee, company: company) }
  let!(:conversation) { create(:conversation, employee: employee, company: company) }
  let!(:discovery_message) { create(:message, conversation: conversation, body: "Discovery reply", reviewer_followup: false) }
  let!(:followup_message) { create(:message, conversation: conversation, body: "Hidden followup", reviewer_followup: true) }

  describe "GET /api/v1/company/conversations" do
    it "lists company conversations" do
      get "/api/v1/company/conversations", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["conversations"].length).to eq(1)
      expect(body["conversations"].first["employee_name"]).to eq(employee.display_name)
    end
  end

  describe "GET /api/v1/company/conversations/:id" do
    it "returns conversation messages excluding reviewer followups" do
      get "/api/v1/company/conversations/#{conversation.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      bodies = body["messages"].map { |m| m["body"] }
      expect(bodies).to include("Discovery reply")
      expect(bodies).not_to include("Hidden followup")
    end
  end
end
