# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Consultant::DeepDiveSuggestions", type: :request do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:consultant) { create(:consultant_user) }
  let!(:assignment) { create(:consultant_assignment, consultant_user: consultant, company: company) }
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          state_snapshot: { "blackboard" => { "dossier" => { "slots" => {} } } })
  end
  let(:package) do
    DiscoveryPackage.create!(conversation: conversation, employee: employee, company: company,
                             version: 1, status: "ready", recommendation: "Automate matching.")
  end

  def headers_for(user)
    token = JsonWebToken.encode(
      { sub: "consultant_user:#{user.id}", aud: "consultant", role: "consultant", jti: user.jti }
    )
    { "Authorization" => "Bearer #{token}" }
  end

  let(:headers) { headers_for(consultant) }

  def path(suffix = "")
    "/api/v1/consultant/companies/#{company.id}/discovery_packages/#{package.id}/deep_dive_suggestions#{suffix}"
  end

  describe "GET index" do
    before do
      allow_any_instance_of(Langgraph::Client).to receive(:suggest_deep_dive_questions!).and_return(
        "suggestions" => [
          { "body" => "How long does the re-keying take in a week?",
            "rationale" => "They described it but never put a time to it.", "kind" => "quantify" }
        ],
        "generated_by" => "llm"
      )
    end

    it "returns each suggestion with the reason it is worth asking" do
      get path, headers: headers

      expect(response).to have_http_status(:ok)
      suggestion = response.parsed_body["suggestions"].first
      expect(suggestion["body"]).to eq("How long does the re-keying take in a week?")
      expect(suggestion["rationale"]).to eq("They described it but never put a time to it.")
      expect(response.parsed_body["budget_remaining"]).to be_positive
    end

    # Looking is free. If merely opening the review spent budget or queued a
    # question, a consultant could not browse without committing the employee.
    it "changes nothing" do
      expect { get path, headers: headers }.to change(DiscoveryFollowupQuestion, :count).by(0)
      expect(ConsultantRequirement.count).to eq(0)
    end

    it "refuses a consultant not assigned to this company" do
      get path, headers: headers_for(create(:consultant_user))

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an unauthenticated caller" do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST create" do
    let(:body) { "Roughly how long does the re-keying take you in a week?" }
    let(:rationale) { "They described re-keying but never put a time to it." }

    it "turns an accepted suggestion into a queued question" do
      post path, params: { body: body, rationale: rationale }, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["question"]["body"]).to eq(body)
      expect(response.parsed_body["question"]["status"]).to eq("drafted")

      requirement = ConsultantRequirement.find(response.parsed_body["requirement_id"])
      expect(requirement.consultant_user).to eq(consultant)
      expect(requirement.statement).to eq(rationale)
    end

    it "reports an exhausted budget as a refusal, not a crash" do
      allow(Discovery::FollowupLimits).to receive(:package_budget_remaining).and_return(0)

      post path, params: { body: body, rationale: rationale }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to be_present
    end

    it "rejects an empty question" do
      post path, params: { body: "", rationale: rationale }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a consultant not assigned to this company" do
      post path, params: { body: body, rationale: rationale }, headers: headers_for(create(:consultant_user))

      expect(response).to have_http_status(:not_found)
      expect(ConsultantRequirement.count).to eq(0)
    end
  end
end
