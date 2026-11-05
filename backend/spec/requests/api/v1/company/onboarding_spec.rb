# frozen_string_literal: true

require "rails_helper"

# The Doc 07 onboarding form, end to end through the API.
RSpec.describe "Company onboarding form", type: :request do
  let(:company) { create(:company, display_name: "Al Noor Trading") }
  let(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }
  let!(:engagement) { create(:engagement, company: company, status: "ONBOARDING", key_user: user) }

  def autosave(answers)
    patch "/api/v1/company/onboarding/questionnaire/answers", params: { answers: answers }, headers: headers, as: :json
  end

  def save_group(answers)
    patch "/api/v1/company/onboarding/questionnaire", params: { answers: answers, questionnaire_step: 2 },
                                                      headers: headers, as: :json
  end

  def submit(answers = {}, acknowledged = true) # rubocop:disable Style/OptionalBooleanParameter
    post "/api/v1/company/onboarding/submit",
         params: { answers: answers, confidentiality_acknowledged: acknowledged }, headers: headers, as: :json
  end

  describe "autosave" do
    it "stores the form's answers and nothing it doesn't know" do
      autosave(o01_industry: "Wholesale & distribution", q31_operational_challenges: "Approvals stall",
               q40_desired_outcomes: ["Growth"], budget: "AED 1m")

      expect(response).to have_http_status(:ok)
      # The old questionnaire's questions are gone from what can be stored (Doc 07 §16).
      expect(company.reload.questionnaire_answers).to eq("o01_industry" => "Wholesale & distribution")
    end

    it "refuses a value that isn't one of a field's options" do
      autosave(o02_headcount: "About 40")
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "clears an answer sent as null, and the profile with it once saved" do
      save_group(o02_headcount: "11–50")
      autosave(o02_headcount: nil)
      expect(company.reload.questionnaire_answers["o02_headcount"]).to be_nil

      save_group({})
      expect(company.reload.company_profile).not_to have_key("size_band")
    end

    it "keeps the profile as it was until a group is saved" do
      autosave(o01_industry: "Manufacturing")
      expect(company.reload.company_profile).to eq({})
    end
  end

  describe "saving a group" do
    it "folds the answers into the profile, the systems and the department plan, recording provenance" do
      save_group(
        o01_industry: "Wholesale & distribution", o01_industry_detail: "Tailoring materials",
        o02_headcount: "51–200", o03_hq_country: "United Arab Emirates", o03_locations: "Dubai, Riyadh",
        o04_business_model: %w[B2B Wholesale], o05_products_services: "Fabrics and garment accessories",
        o06_departments: %w[Sales Procurement Other], o06_departments_other: "Showroom",
        o07_channels: ["WhatsApp", "Online store"], o08_systems: %w[ERP Spreadsheets Other],
        o08_systems_other: "Zoho Books", o10_ai_tools: ["None"], o11_constraints: "Not sure",
        p1_departments: %w[Sales Procurement], p2_department_counts: { "Sales" => "2", "Procurement" => "Not sure" },
        a4_language: "Arabic"
      )

      expect(response).to have_http_status(:ok)
      company.reload
      expect(company.company_profile).to include(
        "industry" => "wholesale_distribution", "industry_detail" => "Tailoring materials", "size_band" => "51-200",
        "country" => "United Arab Emirates", "locations" => %w[Dubai Riyadh], "business_model" => %w[B2B WHOLESALE],
        "org_departments" => %w[Sales Procurement Showroom], "customer_channels" => %w[WHATSAPP ONLINE_STORE],
        "current_ai_use" => ["None"]
      )
      expect(company.company_profile).not_to have_key("security_constraints")
      expect(company.profile_provenance["security_constraints"]).to include("unknown" => true)
      expect(company.profile_provenance.dig("industry", "source")).to eq("USER_ENTERED")
      expect(company.company_systems.active.pluck(:name)).to contain_exactly("ERP", "Zoho Books")
      expect(engagement.reload.planned_departments).to eq([{ "name" => "Sales", "count" => 2 },
                                                           { "name" => "Procurement", "count" => "UNKNOWN" }])
      expect(engagement.planned_participant_count).to be_nil
      expect(user.reload.preferred_language).to eq("ar")
    end

    it "doesn't relabel a confirmed fact as typed when the form is saved again unchanged" do
      company.update!(company_profile: { "industry" => "wholesale_distribution" },
                      profile_provenance: { "industry" => { "source" => "PREFILL_CONFIRMED" } })
      save_group(o01_industry: "Wholesale & distribution")

      expect(company.reload.profile_provenance.dig("industry", "source")).to eq("PREFILL_CONFIRMED")
    end
  end

  describe "submitting" do
    let(:complete) { { p1_departments: ["Sales"], p2_department_counts: { "Sales" => "Not sure" } } }

    it "hands the engagement over to the key-person conversation, with the acknowledgement recorded" do
      expect { submit(complete) }.to have_enqueued_job(KeyPersonKickoffJob).with(engagement.id)

      expect(response).to have_http_status(:ok)
      engagement.reload
      expect(engagement.status).to eq("KEY_PERSON_DISCOVERY")
      expect(engagement.confidentiality_acknowledged_by).to eq(user)
      expect(engagement.confidentiality_text_version).to eq(Companies::OnboardingFields::CONFIDENTIALITY_VERSION)
      expect(engagement.onboarding_submitted_at).to be_present
      expect(company.reload.portal_onboarding_completed_at).to be_present
    end

    # Counts may be "Not sure" here; they are settled before pricing (Doc 07 §10).
    it "accepts departments whose numbers aren't known yet" do
      submit(complete)
      expect(engagement.reload.planned_departments).to eq([{ "name" => "Sales", "count" => "UNKNOWN" }])
    end

    it "needs the acknowledgement" do
      submit(complete, false)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(engagement.reload.status).to eq("ONBOARDING")
    end

    it "needs at least one department" do
      submit
      expect(JSON.parse(response.body)["errors"]).to include("Choose at least one department to take part")
    end

    it "keeps a department engagement to its departments" do
      engagement.update!(scope_type: "DEPARTMENT", departments_in_scope: ["Procurement"])
      submit(complete)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"].first).to match(/Sales is not/)
    end

    it "lets the key user edit facts afterwards without moving the engagement again" do
      submit(complete)
      submit(o02_headcount: "11–50")

      expect(response).to have_http_status(:ok)
      expect(company.reload.company_profile["size_band"]).to eq("11-50")
      expect(engagement.reload.status).to eq("KEY_PERSON_DISCOVERY")
      expect(engagement.status_history.count { |h| h["to"] == "KEY_PERSON_DISCOVERY" }).to eq(1)
    end

    it "keeps a company from before engagements where it is" do
      engagement.update!(status: "STAGE_1_ACTIVE")
      submit(complete)

      expect(response).to have_http_status(:ok)
      expect(engagement.reload.status).to eq("STAGE_1_ACTIVE")
    end
  end

  it "shows the key user what is still missing and the acknowledgement they will agree to" do
    get "/api/v1/company/onboarding", headers: headers

    body = JSON.parse(response.body)
    expect(body["missing_for_submit"]).to include("Choose at least one department to take part")
    expect(body["confidentiality"]["text"]).to include("Al Noor Trading")
    expect(body["engagement"]["status"]).to eq("ONBOARDING")
  end
end
