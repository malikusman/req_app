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
end
