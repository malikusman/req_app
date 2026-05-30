# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::ProfileCompleteness do
  let(:company) { create(:company) }

  it "reports incomplete when no sections saved" do
    result = described_class.call(company: company)
    expect(result[:required_sections_complete]).to be false
    expect(result[:completeness_percent]).to eq(0)
  end

  it "reports complete when all required sections filled" do
    company.update!(
      profile_context: {
        "basics" => {
          "industry" => "technology",
          "company_size_band" => "51-200",
          "hq_country" => "US",
          "one_line_description" => "Test"
        },
        "strategy" => {
          "top_priorities" => ["growth"],
          "transformation_goals" => "Goals",
          "digital_vision_maturity" => "developing",
          "success_metrics" => "KPIs"
        },
        "operations" => {
          "primary_departments" => ["Ops"],
          "key_workflows" => "Flow",
          "systems_tools" => ["ERP"],
          "automation_level" => "developing",
          "operational_pain_points" => "Pain"
        },
        "technology_data" => {
          "it_maturity" => "developing",
          "integration_level" => "Partial",
          "data_governance" => "Informal",
          "security_posture" => "moderate"
        },
        "people_culture" => {
          "org_structure_notes" => "Flat",
          "change_readiness" => "moderate",
          "digital_literacy" => "moderate",
          "collaboration_tools" => "Slack"
        }
      }
    )

    result = described_class.call(company: company.reload)
    expect(result[:required_sections_complete]).to be true
    expect(result[:completeness_percent]).to eq(100)
  end
end
