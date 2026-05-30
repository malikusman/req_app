# frozen_string_literal: true

require "rails_helper"

RSpec.describe Knowledge::ContextBundleService do
  let(:company) do
    create(:company, profile_context: {
      "basics" => {
        "industry" => "technology",
        "company_size_band" => "51-200",
        "hq_country" => "US",
        "one_line_description" => "Acme Corp"
      },
      "gaps_constraints" => { "known_bottlenecks" => "Spreadsheet chaos" }
    })
  end

  it "returns profile and aggregate sections" do
    Employee.create!(
      company: company,
      phone_e164: "+15551234567",
      department: "finance",
      participation_status: "completed",
      agent_profile: {
        "pain_points" => ["slow approvals"],
        "systems_used" => ["Excel"]
      }
    )

    bundle = described_class.call(company: company)

    expect(bundle[:profile_text]).to include("Acme")
    expect(bundle[:gaps_constraints]["known_bottlenecks"]).to eq("Spreadsheet chaos")
    expect(bundle[:employee_profile_aggregate].first[:department]).to eq("finance")
    expect(bundle[:employee_profile_aggregate].first[:pain_points]).to include("slow approvals")
  end
end
