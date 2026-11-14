# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, "#participation" do
  it "counts people, once each, whatever the stored counters say" do
    company = create(:company)
    company.update_columns(invited_count: 5, completed_count: 7)
    create(:employee, company: company, participation_status: "completed")
    create(:employee, company: company, participation_status: "started")
    create(:employee, company: company, participation_status: "invited")

    expect(company.participation).to eq("invited" => 3, "started" => 2, "completed" => 1, "completion_rate" => 0.33)
    expect([company.invited_count, company.completed_count]).to eq([3, 1])
  end
end
