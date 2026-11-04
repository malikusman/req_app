# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::ProfileUpdater do
  let(:company) { create(:company) }

  it "stores firmographics and seeds manual CompanySystem rows" do
    described_class.call(
      company: company,
      profile_params: {
        "industry" => "logistics",
        "size_band" => "51-200",
        "region" => "UAE",
        "business_goals" => "Cut month-end close"
      },
      known_systems: ["SAP", "Excel"]
    )

    company.reload
    expect(company.company_profile["industry"]).to eq("logistics")
    expect(company.company_profile["size_band"]).to eq("51-200")
    expect(company.company_systems.active.pluck(:name)).to contain_exactly("SAP", "Excel")
    expect(company.company_systems.find_by(normalized_name: "sap").source).to eq("manual")
    expect(company.company_systems.find_by(normalized_name: "sap").category).to eq("erp")
  end

  it "never stores goals or revenue, whatever the caller sends" do
    described_class.call(company: company,
                         profile_params: { "industry" => "retail", "business_goals" => ["Grow"],
                                           "annual_revenue_band" => "1m_10m" })

    expect(company.reload.company_profile.keys).to eq(["industry"])
  end

  it "records where each value came from, and who gave it" do
    user = create(:company_user, company: company)
    described_class.call(company: company, profile_params: { "industry" => "retail" },
                         provenance: "PREFILL_CONFIRMED", actor: user)

    entry = company.reload.profile_provenance["industry"]
    expect(entry).to include("source" => "PREFILL_CONFIRMED", "by_type" => "CompanyUser", "by_id" => user.id)
  end

  it "records Not sure as an answer without storing it as a value" do
    company.update!(company_profile: { "size_band" => "51-200" })
    described_class.call(company: company, profile_params: { "size_band" => "UNKNOWN" })

    company.reload
    expect(company.company_profile).not_to have_key("size_band")
    expect(company.profile_provenance["size_band"]).to include("unknown" => true)
  end

  it "keeps a system's original source when the client names it too" do
    company.company_systems.create!(name: "SAP", normalized_name: "sap", category: "erp",
                                    source: "inferred_document", confidence: 0.6, active: true)
    described_class.call(company: company, known_systems: ["SAP"])

    sap = company.company_systems.find_by(normalized_name: "sap")
    expect(sap.source).to eq("inferred_document")
    expect(sap.confidence).to eq(1.0)
  end

  it "rejects an unknown provenance" do
    expect { described_class.call(company: company, provenance: "GUESSED") }.to raise_error(ArgumentError)
  end

  describe "change history" do
    include ActiveJob::TestHelper

    let(:user) { create(:company_user, company: company) }
    let!(:engagement) { create(:engagement, company: company, status: "ONBOARDING") }

    before do
      described_class.call(company: company, profile_params: { "size_band" => "11-50", "industry" => "retail" },
                           known_systems: ["Excel"], actor: user)
    end

    it "keeps nothing while the client is still filling in onboarding" do
      expect(company.profile_changes).to be_empty
    end

    context "once onboarding is submitted" do
      before { engagement.update!(onboarding_submitted_at: Time.current) }

      it "records each changed field, what it was and became, where from and who" do
        described_class.call(company: company, profile_params: { "size_band" => "51-200", "industry" => "retail" },
                             actor: user, only_changed: true)

        change = company.profile_changes.sole
        expect(change).to have_attributes(field: "size_band", from_value: "11-50", to_value: "51-200",
                                          source: "USER_ENTERED", actor: user)
      end

      it "records nothing when a save changes nothing, even one that rewrites every field" do
        described_class.call(company: company, profile_params: { "size_band" => "11-50", "industry" => "retail" })

        expect(company.profile_changes).to be_empty
      end

      it "records Not sure as such" do
        described_class.call(company: company, profile_params: { "size_band" => "UNKNOWN" }, actor: user)

        expect(company.profile_changes.sole).to have_attributes(from_value: "11-50", to_value: "UNKNOWN")
      end

      it "records a new website and new systems" do
        described_class.call(company: company, website_url: "example-trading.ae", known_systems: %w[Excel SAP],
                             actor: user)

        expect(company.profile_changes.pluck(:field, :from_value, :to_value)).to contain_exactly(
          ["website_url", nil, "https://example-trading.ae"],
          ["company_systems", ["Excel"], %w[Excel SAP]]
        )
      end
    end
  end
end
