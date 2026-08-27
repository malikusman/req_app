# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform company profile + consultant cards", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }

  describe "GET /api/v1/platform/companies/:id" do
    let(:company) do
      create(
        :company,
        company_profile: { "industry" => "retail", "size_band" => "51-200" },
        questionnaire_answers: {
          "company_industry" => "Retail & E-commerce",
          "company_size" => "51–200",
          "primary_goals" => ["Cut manual work"]
        }
      )
    end

    it "includes company profile and questionnaire progress" do
      get "/api/v1/platform/companies/#{company.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      c = body["company"]
      expect(c["company_profile"]["industry"]).to eq("retail")
      expect(c["questionnaire_answers"]["company_industry"]).to eq("Retail & E-commerce")
      expect(c).to have_key("questionnaire_completion_percent")
      expect(c["questionnaire_completion_percent"]).to be > 0
    end
  end

  describe "consultant public_card" do
    let(:consultant) do
      create(
        :consultant_user,
        status: "active",
        headline: "Ops leader",
        bio: "B" * 40,
        expertise_tags: %w[Ops Supply Finance],
        industries: ["Manufacturing"]
      ).tap do |r|
        r.consultant_experiences.create!(organization: "Acme", title: "Director", start_year: 2018, sort_order: 0)
      end
    end

    it "includes bio and experiences on company expert consultants" do
      company = create(:company)
      create(:consultant_assignment, company: company, consultant_user: consultant, status: "active")
      consultant.update!(profile_status: "published", profile_completed_at: Time.current)

      company_user = create(:company_user, company: company, role: "company_admin", status: "active")
      get "/api/v1/company/expert_consultants", headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:ok)
      card = JSON.parse(response.body)["expert_consultants"].first
      expect(card["bio"]).to eq(consultant.bio)
      expect(card["experiences"].first["organization"]).to eq("Acme")
      expect(card["industries"]).to include("Manufacturing")
    end
  end

  describe "GET /api/v1/platform/consultants/:id/cv" do
    let(:consultant) { create(:consultant_user, status: "active", cv_storage_key: nil) }

    it "returns 404 when no CV" do
      get "/api/v1/platform/consultants/#{consultant.id}/cv", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "streams CV when present" do
      consultant.update!(cv_storage_key: "consultants/#{consultant.id}/cv/test.pdf")
      client = instance_double(Storage::MinioClient, download: "%PDF-1.4 fake")
      allow(Storage::MinioClient).to receive(:new).and_return(client)

      get "/api/v1/platform/consultants/#{consultant.id}/cv", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to include("%PDF")
    end
  end

  describe "GET /api/v1/platform/consultants/:id" do
    let(:consultant) { create(:consultant_user, status: "active", cv_storage_key: "consultants/1/cv/x.pdf") }

    it "returns detailed profile with has_cv and platform cv_url" do
      get "/api/v1/platform/consultants/#{consultant.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["consultant"]
      expect(body["has_cv"]).to eq(true)
      expect(body["profile"]["cv_url"]).to eq("/api/v1/platform/consultants/#{consultant.id}/cv")
    end
  end
end
