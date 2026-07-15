# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmployeeValue::GenerateDigestService do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, email: "ava@example.com", department: "finance", role_title: "AP Specialist")
  end

  before do
    EmployeeValuePreference.create!(
      employee: employee,
      email_opt_in: true,
      frequency: "monthly",
      interests: %w[approvals automation]
    )
    create(:company_signal, company: company, signal_type: "approval_bottleneck", strength: 0.9, departments: ["finance"])
    Pattern.create!(
      company: company,
      title: "Approval bottleneck across manual workflows",
      description: "Manual work plus slow approvals",
      confidence: 0.82,
      departments: ["finance"],
      linked_signal_ids: [],
      first_seen_at: Time.current,
      last_updated_at: Time.current,
      status: "confirmed"
    )
  end

  it "builds a private digest with tips, tools shape, and interest-aware intro" do
    digest = described_class.call(employee: employee, period_key: "2026-07")

    expect(digest.period_key).to eq("2026-07")
    expect(digest.content["privacy_note"]).to be_present
    expect(digest.content["greeting"]).to include("Ava").or include("there").or include("Hi")
    expect(digest.content["intro"]).to include("approvals")
    expect(digest.content["tips"]).to be_an(Array)
    expect(digest.content["tips"]).not_to be_empty
    expect(digest.content["team_theme"]).to include("Approval bottleneck")
    expect(digest.content["interests_used"]).to include("approvals")
    expect(digest.status).to eq("draft")
    expect(digest.model_version).to eq("employee-value-v2")
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
