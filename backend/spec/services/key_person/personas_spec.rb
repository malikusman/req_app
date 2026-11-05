# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::Personas do
  {
    "CEO" => "CEO_OWNER_MD",
    "Owner & Managing Director" => "CEO_OWNER_MD",
    "Co-founder" => "CEO_OWNER_MD",
    "Chairman" => "CEO_OWNER_MD",
    "General Manager" => "GM_COO",
    "Chief Operating Officer" => "GM_COO",
    "CFO" => "CFO_FINANCE",
    "Chief Financial Officer" => "CFO_FINANCE",
    "Finance Director" => "CFO_FINANCE",
    "Head of Sales" => "SALES_COMMERCIAL",
    "Commercial Director" => "SALES_COMMERCIAL",
    "Procurement Manager" => "PROCUREMENT_SUPPLY",
    "Head of Supply Chain" => "PROCUREMENT_SUPPLY",
    "Marketing Lead" => "MARKETING",
    "Customer Service Manager" => "CUSTOMER_SERVICE",
    "HR Manager" => "HR",
    "Head of IT" => "IT_DIGITAL",
    "Operations Director" => "OPERATIONS",
    "Head of Projects" => "DEPARTMENT_HEAD",
    "الرئيس التنفيذي" => "CEO_OWNER_MD",
    "المدير العام" => "GM_COO",
    "مدير المبيعات" => "SALES_COMMERCIAL",
    "مدير المشتريات" => "PROCUREMENT_SUPPLY",
    "Partner" => "OTHER",
    "" => "OTHER"
  }.each do |title, persona|
    it "reads #{title.inspect} as #{persona}" do
      expect(described_class.from_title(title)).to eq(persona)
    end
  end

  it "weights functional heads as department heads (Doc 08 §8.2)" do
    expect(described_class.column("SALES_COMMERCIAL")).to eq(:department_head)
    expect(described_class.column("CEO_OWNER_MD")).to eq(:ceo)
    expect(KeyPerson::Coverage.weight("GROWTH_PRIORITIES", "CEO_OWNER_MD")).to eq(3)
    expect(KeyPerson::Coverage.weight("GROWTH_PRIORITIES", "DEPARTMENT_HEAD")).to eq(1)
    expect(KeyPerson::Coverage.weight("RELEASED_TIME", "DEPARTMENT_HEAD")).to eq(3)
  end
end
