# frozen_string_literal: true

require "rails_helper"

# Confirming or correcting what the website said (Doc 07 §5.4, §16).
RSpec.describe "Onboarding website proposals", type: :request do
  let(:company) { create(:company, website_url: "https://example-trading.ae") }
  let(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }
  let!(:engagement) { create(:engagement, company: company, status: "ONBOARDING", key_user: user, prefill_status: "done") }

  def propose(field, value, display = nil)
    engagement.prefill_candidates.create!(
      company: company, target_field: field, value: value, display_text: display, confidence: "HIGH",
      source_url: "https://example-trading.ae/", evidence_excerpt: "leading wholesalers of tailoring materials",
      website_url: company.website_url, prompt_version: "P01.v1", extracted_at: Time.current
    )
  end

  def act(candidate, action)
    post "/api/v1/company/onboarding/prefill_candidates/#{candidate.id}/#{action}", headers: headers, as: :json
  end

  it "shows the proposals with their evidence on the onboarding screen" do
    propose("industry", "Wholesale distribution — tailoring materials", "Wholesaler of tailoring materials")

    get "/api/v1/company/onboarding", headers: headers

    prefill = JSON.parse(response.body)["prefill"]
    expect(prefill["status"]).to eq("done")
    expect(prefill["candidates"].first).to include("target_field" => "industry", "status" => "PROPOSED",
                                                   "display_text" => "Wholesaler of tailoring materials",
                                                   "evidence_excerpt" => "leading wholesalers of tailoring materials")
  end

  it "makes a confirmed proposal a fact, recorded as confirmed from the website" do
    candidate = propose("industry", "Wholesale distribution — tailoring materials", "Wholesaler of tailoring materials")

    act(candidate, :confirm)

    expect(response).to have_http_status(:ok)
    company.reload
    expect(company.company_profile).to include("industry" => "wholesale_distribution",
                                               "industry_detail" => "Wholesaler of tailoring materials")
    expect(company.profile_provenance.dig("industry", "source")).to eq("PREFILL_CONFIRMED")
    expect(company.questionnaire_answers["o01_industry"]).to eq("Wholesale & distribution")
    expect(candidate.reload).to have_attributes(status: "CONFIRMED", decided_by: user)
  end

  it "stores a correction as the key user's own, keeping the website's value as evidence" do
    candidate = propose("customer_channels", %w[EMAIL WHATSAPP])

    act(candidate, :correct)
    expect(JSON.parse(response.body)["answers"]).to eq("o07_channels" => %w[Email WhatsApp])

    patch "/api/v1/company/onboarding/questionnaire", params: { answers: { o07_channels: %w[WhatsApp Phone] } },
                                                      headers: headers, as: :json
    company.reload
    expect(company.company_profile["customer_channels"]).to eq(%w[WHATSAPP PHONE])
    expect(company.profile_provenance.dig("customer_channels", "source")).to eq("USER_ENTERED")
    expect(candidate.reload).to have_attributes(status: "CORRECTED", value: %w[EMAIL WHATSAPP])
  end

  it "writes nothing for a rejected proposal" do
    candidate = propose("locations", ["Dubai"])
    act(candidate, :reject)

    expect(candidate.reload.status).to eq("REJECTED")
    expect(company.reload.company_profile).to eq({})
  end

  # Doc 07 §16: a value the key user ignores stays INFERRED, and is not used as fact.
  it "keeps a proposal nobody acted on out of everything that reads the profile" do
    propose("products_services", "SENTINEL-UNCONFIRMED-PRODUCTS")

    expect(company.reload.company_profile.to_json).not_to include("SENTINEL")
    expect(Companies::AgentContext.for_agents(company).to_json).not_to include("SENTINEL")
    expect(Companies::AgentContext.docs_profile_snapshot(company).to_json).not_to include("SENTINEL")
    expect(Companies::AgentContext.consultant_profile_json(company).to_json).not_to include("SENTINEL")
  end

  it "turns a confirmed value into a correction once the key user changes it by hand" do
    candidate = propose("industry", "Wholesale distribution")
    act(candidate, :confirm)

    patch "/api/v1/company/onboarding/questionnaire", params: { answers: { o01_industry: "Manufacturing" } },
                                                      headers: headers, as: :json

    expect(candidate.reload.status).to eq("CORRECTED")
    expect(company.reload.profile_provenance.dig("industry", "source")).to eq("USER_ENTERED")
  end

  it "flags a proposal that disagrees with something the key user already entered, without applying it" do
    company.update!(company_profile: { "industry" => "manufacturing" },
                    profile_provenance: { "industry" => { "source" => "USER_ENTERED" } })
    propose("industry", "Wholesale distribution")

    get "/api/v1/company/onboarding", headers: headers

    expect(JSON.parse(response.body).dig("prefill", "candidates", 0, "conflicts")).to be(true)
    expect(company.reload.company_profile["industry"]).to eq("manufacturing")
  end

  it "answers each proposal once, and only on this engagement" do
    candidate = propose("locations", ["Dubai"])
    act(candidate, :reject)
    act(candidate, :confirm)
    expect(response).to have_http_status(:unprocessable_entity)

    other = create(:engagement).prefill_candidates.create!(
      company: create(:company), target_field: "locations", value: ["X"], confidence: "HIGH", source_url: "u",
      evidence_excerpt: "e", website_url: "w", prompt_version: "P01.v1", extracted_at: Time.current
    )
    act(other, :confirm)
    expect(response).to have_http_status(:not_found)
  end
end
