# frozen_string_literal: true

require "rails_helper"

# A consultant correcting the client's facts after onboarding (Doc 07 §12): the
# same validation as the key user's form, recorded as found later in
# conversation, by that consultant, and kept in the change history.
RSpec.describe "Consultant: correcting a company's facts", type: :request do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }
  let!(:engagement) { create(:engagement, company: company, status: "ONBOARDING") }
  let(:path) { "/api/v1/consultant/companies/#{company.id}/facts" }

  before do
    company.update!(questionnaire_answers: { "o02_headcount" => "11–50", "o07_channels" => %w[WhatsApp] })
    Companies::OnboardingSync.call(company: company, answers: company.questionnaire_answers,
                                   actor: create(:company_user, company: company))
    engagement.update!(status: "KEY_PERSON_DISCOVERY", onboarding_submitted_at: 1.day.ago)
  end

  def save(answers)
    patch path, params: { answers: answers }, headers: auth_headers_for(consultant), as: :json
  end

  it "updates the fact, recorded as found later and by this consultant, and keeps the change" do
    save(o02_headcount: "51–200")

    expect(response).to have_http_status(:ok)
    company.reload
    expect(company.company_profile["size_band"]).to eq("51-200")
    expect(company.profile_provenance["size_band"]).to include("source" => "DISCOVERED_LATER",
                                                               "by_type" => "ConsultantUser", "by_id" => consultant.id)
    expect(company.profile_provenance.dig("customer_channels", "source")).to eq("USER_ENTERED")
    expect(company.profile_changes.sole).to have_attributes(field: "size_band", from_value: "11-50",
                                                            to_value: "51-200", actor: consultant)
    expect(JSON.parse(response.body)["profile_changes"].first).to include("field" => "size_band")
  end

  it "clears a fact sent as null, as the form does when an answer is unselected" do
    save(o02_headcount: nil)

    expect(response).to have_http_status(:ok)
    expect(company.reload.company_profile).not_to have_key("size_band")
    expect(company.profile_changes.sole).to have_attributes(field: "size_band", from_value: "11-50", to_value: nil)
  end

  it "leaves who takes part and the key user's language alone" do
    save(o02_headcount: "51–200", p1_departments: %w[Sales], p2_department_counts: { "Sales" => "4" },
         a4_language: "Arabic")

    expect(company.reload.questionnaire_answers.keys).not_to include("p1_departments", "p2_department_counts",
                                                                     "a4_language")
    expect(engagement.reload.planned_departments).to eq([])
  end

  it "turns a confirmed website proposal for that field into a correction" do
    candidate = create_candidate(target_field: "industry", status: "CONFIRMED")
    company.update!(profile_provenance: company.profile_provenance.merge(
      "industry" => { "source" => "PREFILL_CONFIRMED", "at" => Time.current.iso8601 }
    ), company_profile: company.company_profile.merge("industry" => "retail"))

    save(o01_industry: "Manufacturing")

    expect(candidate.reload.status).to eq("CORRECTED")
  end

  it "refuses a value that isn't one of the field's options" do
    save(o02_headcount: "a few")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(company.reload.company_profile["size_band"]).to eq("11-50")
  end

  it "waits until the client has submitted onboarding" do
    engagement.update!(onboarding_submitted_at: nil, status: "ONBOARDING")
    save(o02_headcount: "51–200")

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "is only for consultants assigned to the company" do
    patch path, params: { answers: { o02_headcount: "51–200" } }, headers: auth_headers_for(create(:consultant_user)),
                as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "shows the answers, sources and changes on the company page" do
    get "/api/v1/consultant/companies/#{company.id}", headers: auth_headers_for(consultant)

    body = JSON.parse(response.body)["company"]
    expect(body["onboarding_answers"]).to include("o02_headcount" => "11–50")
    expect(body["profile_provenance"]).to have_key("size_band")
    expect(body["onboarding_submitted_at"]).to be_present
    expect(body["profile_changes"]).to eq([])
  end

  def create_candidate(**attrs)
    engagement.prefill_candidates.create!(
      company: company, value: "Retail", display_text: "Retail", confidence: "HIGH",
      source_url: "https://example.ae/", evidence_excerpt: "a retailer", website_url: "https://example.ae",
      prompt_version: "P01.v1", extracted_at: Time.current, **attrs
    )
  end
end
