# frozen_string_literal: true

require "rails_helper"

# Autosave is the only way answers reach the server — there is no Save button — so
# the cheap path has to be correct about what it stores and what it refuses.
RSpec.describe "Company onboarding autosave", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }
  let(:path) { "/api/v1/company/onboarding/questionnaire/answers" }

  def autosave(answers)
    patch path, params: { questionnaire_answers: answers }, headers: headers, as: :json
  end

  it "stores an answer" do
    autosave(q01_primary_industry: "IT & Software")

    expect(response).to have_http_status(:ok)
    expect(company.reload.questionnaire_answers["q01_primary_industry"]).to eq("IT & Software")
  end

  # Each save sends only what changed, so it must merge rather than replace —
  # otherwise every keystroke would wipe the rest of the questionnaire.
  it "merges into what is already stored rather than replacing it" do
    company.update!(questionnaire_answers: { "q01_primary_industry" => "Retail & E-commerce" })

    autosave(q02_business_description: "We ship things.")

    answers = company.reload.questionnaire_answers
    expect(answers["q01_primary_industry"]).to eq("Retail & E-commerce")
    expect(answers["q02_business_description"]).to eq("We ship things.")
  end

  it "stores the keyed map the matrix questions produce" do
    autosave(q29_external_parties_channels: { "customers / clients" => %w[email WhatsApp] })

    expect(company.reload.questionnaire_answers["q29_external_parties_channels"])
      .to eq("customers / clients" => %w[email WhatsApp])
  end

  it "stores the Other free text and the per-selection detail" do
    autosave(
      q01_primary_industry_other: "Marine services",
      q21_high_volume_activity_detail: { "invoices" => "500/day" }
    )

    answers = company.reload.questionnaire_answers
    expect(answers["q01_primary_industry_other"]).to eq("Marine services")
    expect(answers["q21_high_volume_activity_detail"]).to eq("invoices" => "500/day")
  end

  it "drops a key the questionnaire does not define" do
    autosave(not_a_question: "x", q01_primary_industry: "Education")

    answers = company.reload.questionnaire_answers
    expect(answers).not_to have_key("not_a_question")
    expect(answers["q01_primary_industry"]).to eq("Education")
  end

  # Old v1 keys are no longer part of the questionnaire. Accepting them would let
  # a stale client quietly repopulate data nothing reads.
  it "drops a retired v1 key" do
    autosave(company_industry: "IT & Software")

    expect(company.reload.questionnaire_answers).not_to have_key("company_industry")
  end

  it "refuses Other text beyond the cap instead of truncating it" do
    autosave(q01_primary_industry_other: "x" * 200)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(company.reload.questionnaire_answers).not_to have_key("q01_primary_industry_other")
  end

  it "cleans control characters and surrounding space out of free text" do
    autosave(q01_primary_industry_other: "  Marine\u0007 services  ")

    expect(company.reload.questionnaire_answers["q01_primary_industry_other"]).to eq("Marine services")
  end

  # The heavy work — profile sync, completion stamping, step tracking — belongs on
  # a step change, not on every keystroke.
  it "does not advance the step or stamp completion" do
    company.update!(questionnaire_step: 3)

    autosave(q01_primary_industry: "Education")

    company.reload
    expect(company.questionnaire_step).to eq(3)
    expect(company.questionnaire_completed_at).to be_nil
  end

  it "refuses an unauthenticated caller" do
    patch path, params: { questionnaire_answers: { q01_primary_industry: "Education" } }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
