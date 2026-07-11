# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmployeeValue::GenerateDigestService do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, email: "ava@example.com") }

  it "builds a private digest for the employee" do
    digest = described_class.call(employee: employee, period_key: "2026-07")

    expect(digest.period_key).to eq("2026-07")
    expect(digest.content["privacy_note"]).to be_present
    expect(digest.status).to eq("draft")
  end
end

RSpec.describe EmployeeValuePreference do
  let(:employee) { create(:employee) }

  it "tracks opt-in subscription state" do
    pref = described_class.create!(employee: employee, email_opt_in: true, frequency: "monthly")
    expect(pref).to be_subscribed
    expect(described_class.opted_in).to include(pref)

    pref.update!(email_opt_in: false, unsubscribed_at: Time.current)
    expect(pref).not_to be_subscribed
  end
end
