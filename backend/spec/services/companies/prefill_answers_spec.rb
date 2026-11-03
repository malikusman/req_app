# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::PrefillAnswers do
  def answers_for(field, value, display = nil)
    described_class.for(PrefillCandidate.new(target_field: field, value: value, display_text: display))
  end

  it "places the industry the website describes, keeping its words as the detail" do
    expect(answers_for("industry", "Wholesale distribution — tailoring materials", "Wholesaler of tailoring materials"))
      .to eq("o01_industry" => "Wholesale & distribution", "o01_industry_detail" => "Wholesaler of tailoring materials")
  end

  it "uses Other for an industry the form has no option for" do
    expect(answers_for("industry", "Marine salvage")).to include("o01_industry" => "Other",
                                                                 "o01_industry_other" => "Marine salvage")
  end

  it "turns P01's codes into the form's options" do
    expect(answers_for("business_model", %w[B2B WHOLESALE OTHER])).to eq("o04_business_model" => %w[B2B Wholesale Other])
    expect(answers_for("customer_channels", %w[ONLINE_STORE IN_PERSON])).to eq("o07_channels" => ["Online store", "In person"])
  end

  it "matches named departments, systems and AI tools, and puts the rest under Other" do
    expect(answers_for("departments", %w[sales Showroom])).to eq("o06_departments" => %w[Sales Other],
                                                                 "o06_departments_other" => "Showroom")
    expect(answers_for("core_systems", %w[Shopify])).to eq("o08_systems" => ["Other"], "o08_systems_other" => "Shopify")
    expect(answers_for("ai_tools", ["ChatGPT"])).to eq("o10_ai_tools" => ["ChatGPT"])
  end

  it "fills the free-text fields" do
    expect(answers_for("locations", %w[Dubai Riyadh])).to eq("o03_locations" => "Dubai, Riyadh")
    expect(answers_for("products_services", "Fabrics")).to eq("o05_products_services" => "Fabrics")
  end

  it "only ever produces answers the form accepts" do
    produced = [answers_for("industry", "Retail"), answers_for("business_model", %w[B2C]),
                answers_for("departments", %w[HR Lab])].reduce(:merge)
    _clean, errors = Companies::OnboardingFields.sanitize(produced)
    expect(errors).to be_empty
  end
end
