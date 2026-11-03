# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::LegacyProfileMigration do
  let(:company) do
    create(:company,
           company_profile: { "industry" => "retail", "size_band" => "51-200",
                              "business_goals" => ["Faster close"], "annual_revenue_band" => "1m_10m" })
  end

  it "moves goals and revenue to legacy_profile and records provenance for what stays" do
    described_class.call(company)
    company.reload

    expect(company.company_profile).to eq("industry" => "retail", "size_band" => "51-200")
    expect(company.legacy_profile).to eq("business_goals" => ["Faster close"], "annual_revenue_band" => "1m_10m")
    expect(company.profile_provenance.keys).to contain_exactly("industry", "size_band")
    expect(company.profile_provenance.dig("industry", "source")).to eq("USER_ENTERED")
  end

  it "marks provenance as the old questionnaire when the company answered it" do
    company.update!(questionnaire_answers: { "q01_primary_industry" => "Retail & E-commerce" })
    described_class.call(company)

    expect(company.reload.profile_provenance.dig("industry", "source")).to eq("LEGACY_QUESTIONNAIRE")
  end

  it "is safe to run twice" do
    described_class.call(company)
    described_class.call(company.reload)

    expect(company.reload.legacy_profile["business_goals"]).to eq(["Faster close"])
    expect(company.company_profile).not_to have_key("business_goals")
  end

  describe "sizes from the old vocabulary" do
    it "recomputes the band from the original answer" do
      company.update!(company_profile: { "size_band" => "201-1000" },
                      questionnaire_answers: { "q03_employee_count" => "501–1,000" })
      described_class.call(company)

      expect(company.reload.company_profile["size_band"]).to eq("501-1000")
    end

    it "keeps an ambiguous band for the consultant instead of guessing" do
      company.update!(company_profile: { "size_band" => "500+" })
      described_class.call(company)

      company.reload
      expect(company.company_profile).not_to have_key("size_band")
      expect(company.legacy_profile["size_band_v1"]).to eq("500+")
    end
  end

  it "retires knowledge from analysis that was given the questionnaire, and only that" do
    informed = company.document_analysis_runs.create!(status: "completed",
                                                      profile_snapshot: { "questionnaire_answers" => { "q31" => "x" } })
    clean = company.document_analysis_runs.create!(status: "completed", profile_snapshot: { "company_profile" => {} })
    old = company.company_knowledge_entries.create!(entry_type: "org", title: "A", content: "a",
                                                    status: "active", document_analysis_run: informed)
    kept = company.company_knowledge_entries.create!(entry_type: "org", title: "B", content: "b",
                                                     status: "active", document_analysis_run: clean)

    described_class.call(company)

    expect(old.reload.status).to eq("superseded")
    expect(kept.reload.status).to eq("active")
    expect(informed.reload.profile_snapshot).not_to have_key("questionnaire_answers")
  end
end
