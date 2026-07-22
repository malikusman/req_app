# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Playbooks", type: :request do
  describe "GET /api/v1/internal/playbooks/active" do
    let!(:playbook) { create(:discovery_playbook, department: "finance", active: true) }

    it "returns active playbook with valid internal token" do
      get "/api/v1/internal/playbooks/active", params: { department: "finance" }, headers: internal_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["department"]).to eq("finance")
      expect(body["prompt_block"]).to eq(playbook.prompt_block)
    end

    it "returns not_found when no playbook exists" do
      get "/api/v1/internal/playbooks/active", params: { department: "unknown-dept" }, headers: internal_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns unauthorized without internal token" do
      get "/api/v1/internal/playbooks/active", params: { department: "finance" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized with the wrong internal token" do
      get "/api/v1/internal/playbooks/active",
          params: { department: "finance" },
          headers: { "X-Internal-Token" => "wrong-token" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
