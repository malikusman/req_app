# frozen_string_literal: true

require "rails_helper"

RSpec.describe Engagement do
  let(:company) { create(:company) }

  it "needs departments when the engagement covers only some of the company" do
    engagement = build(:engagement, company: company, scope_type: "DEPARTMENT", departments_in_scope: [])
    expect(engagement).not_to be_valid

    engagement.departments_in_scope = ["Procurement"]
    expect(engagement).to be_valid
  end

  describe "#planned_participant_count" do
    it "adds up the departments" do
      engagement = build(:engagement, planned_departments: [{ "name" => "Sales", "count" => 2 },
                                                            { "name" => "Finance", "count" => 1 }])
      expect(engagement.planned_participant_count).to eq(3)
      expect(engagement.planned_count_for("sales")).to eq(2)
    end

    it "is unknown while any department is still Not sure" do
      engagement = build(:engagement, planned_departments: [{ "name" => "Sales", "count" => 2 },
                                                            { "name" => "Finance", "count" => "UNKNOWN" }])
      expect(engagement.planned_participant_count).to be_nil
      expect(engagement.planned_count_for("Finance")).to be_nil
    end
  end

  describe "Company#current_engagement and #portal_access?" do
    it "uses the engagement in progress, ignoring closed ones" do
      create(:engagement, company: company, status: "CLOSED")
      open = create(:engagement, company: company, status: "ONBOARDING")

      expect(company.current_engagement).to eq(open)
      expect(company.portal_access?).to be(true)
    end

    it "closes the portal when the only engagement is closed, even with a live subscription" do
      create(:engagement, company: company, status: "CLOSED")
      expect(company.portal_access?).to be(false)
    end
  end

  it "keeps a participant on its engagement's company" do
    engagement = create(:engagement, company: company)
    other = create(:company)
    participant = build(:engagement_participant, engagement: engagement, company: other)

    expect(participant).not_to be_valid
  end

  it "refuses the same phone twice in one engagement" do
    engagement = create(:engagement, company: company)
    create(:engagement_participant, engagement: engagement, phone_e164: "+971500000010")

    expect(build(:engagement_participant, engagement: engagement, phone_e164: "+971500000010")).not_to be_valid
  end
end
