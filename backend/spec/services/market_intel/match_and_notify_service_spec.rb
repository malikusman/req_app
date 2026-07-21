# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarketIntel::EmployeeFitService do
  let(:company) { create(:company) }
  let(:employee) do
    create(
      :employee,
      company: company,
      email: "ava@example.com",
      department: "finance",
      role_title: "AP Specialist",
      metadata: { "profile" => { "primary_tools" => %w[SAP Excel] } }
    )
  end

  before do
    EmployeeValuePreference.create!(
      employee: employee,
      email_opt_in: true,
      frequency: "monthly",
      interests: ["ai tools", "automation"]
    )
  end

  def build_candidate(attrs = {})
    CatalogCandidate.create!(
      {
        name: "SAP finance automation copilot",
        entity_type: "tool",
        description: "Automation for SAP finance and Excel workflows",
        summary: "Helps AP specialists automate invoice workflows in finance",
        website_url: "https://example.com/tool",
        confidence: 0.8,
        review_status: "pending",
        analysis_status: "analyzed",
        industries: ["finance"],
        topics: %w[automation llm],
        provenance: { "stub" => false, "source_url" => "https://example.com/tool" }
      }.merge(attrs)
    )
  end

  it "qualifies when fit score is at least 0.8 for analyzed non-stub candidates" do
    candidate = build_candidate
    result = described_class.call(employee: employee, candidate: candidate)

    expect(result[:fit_score]).to be >= 0.8
    expect(result[:qualifies]).to eq(true)
    expect(result[:fit_rationale]).to include("finance")
  end

  it "does not qualify stub candidates even with a high score" do
    candidate = build_candidate(provenance: { "stub" => true })
    result = described_class.call(employee: employee, candidate: candidate)

    expect(result[:qualifies]).to eq(false)
  end

  it "does not qualify stale analysis" do
    candidate = build_candidate(analysis_status: "stale")
    result = described_class.call(employee: employee, candidate: candidate)

    expect(result[:qualifies]).to eq(false)
  end
end

RSpec.describe MarketIntel::MatchAndNotifyService do
  let(:company) { create(:company) }
  let(:employee) do
    create(
      :employee,
      company: company,
      email: "ava@example.com",
      department: "finance",
      role_title: "AP Specialist",
      metadata: { "profile" => { "primary_tools" => %w[SAP Excel] } }
    )
  end

  let!(:preference) do
    EmployeeValuePreference.create!(
      employee: employee,
      email_opt_in: true,
      frequency: "monthly",
      interests: ["ai tools", "automation"]
    )
  end

  def emailable_candidate(name:)
    CatalogCandidate.create!(
      name: name,
      entity_type: "tool",
      description: "Automation for SAP finance and Excel workflows",
      summary: "Helps AP specialists automate invoice workflows in finance",
      website_url: "https://example.com/#{name.parameterize}",
      confidence: 0.8,
      review_status: "pending",
      analysis_status: "analyzed",
      analyzed_at: Time.current,
      industries: ["finance"],
      topics: %w[automation llm],
      provenance: { "stub" => false, "source_url" => "https://example.com/#{name.parameterize}" }
    )
  end

  before do
    allow(MarketAlertsMailer).to receive_message_chain(:alert_email, :deliver_later)
  end

  it "sends personalized alerts for high-fit analyzed candidates" do
    emailable_candidate(name: "SAP finance automation copilot")

    result = described_class.call

    expect(result[:sent]).to eq(1)
    alert = EmployeeMarketAlert.last
    expect(alert.status).to eq("sent")
    expect(alert.fit_score).to be >= 0.8
    expect(alert.email_body["item_name"]).to include("SAP")
    expect(alert.email_body["why"]).to be_present
  end

  it "never emails stub candidates" do
    CatalogCandidate.create!(
      name: "Stub tool",
      entity_type: "tool",
      description: "Automation for SAP finance",
      summary: "finance automation",
      website_url: nil,
      confidence: 0.9,
      review_status: "pending",
      analysis_status: "analyzed",
      analyzed_at: Time.current,
      industries: ["finance"],
      topics: %w[automation],
      provenance: { "stub" => true }
    )

    result = described_class.call
    expect(result[:sent]).to eq(0)
    expect(EmployeeMarketAlert.count).to eq(0)
  end

  it "respects the monthly email cap" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_MARKET_ALERT_MAX_PER_MONTH", "2").and_return("2")

    c1 = emailable_candidate(name: "SAP finance automation copilot A")
    c2 = emailable_candidate(name: "SAP finance automation copilot B")
    c3 = emailable_candidate(name: "SAP finance automation copilot C")

    month = EmployeeMarketAlert.period_month_for
    EmployeeMarketAlert.create!(
      employee: employee,
      company: company,
      catalog_candidate: c1,
      fit_score: 0.9,
      fit_rationale: "prior",
      period_month: month,
      status: "sent",
      sent_at: Time.current,
      email_body: {}
    )
    EmployeeMarketAlert.create!(
      employee: employee,
      company: company,
      catalog_candidate: c2,
      fit_score: 0.9,
      fit_rationale: "prior",
      period_month: month,
      status: "sent",
      sent_at: Time.current,
      email_body: {}
    )

    result = described_class.call
    expect(result[:sent]).to eq(0)
    expect(EmployeeMarketAlert.where(catalog_candidate: c3).count).to eq(0)
  end
end

RSpec.describe MarketIntel::SendAlertService do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, email: "ava@example.com") }
  let(:candidate) do
    CatalogCandidate.create!(
      name: "Stub only",
      entity_type: "tool",
      analysis_status: "analyzed",
      review_status: "pending",
      provenance: { "stub" => true }
    )
  end

  before do
    EmployeeValuePreference.create!(
      employee: employee,
      email_opt_in: true,
      frequency: "monthly",
      interests: ["ai tools"]
    )
  end

  it "raises when the candidate is a stub" do
    alert = EmployeeMarketAlert.create!(
      employee: employee,
      company: company,
      catalog_candidate: candidate,
      fit_score: 0.95,
      fit_rationale: "test",
      period_month: EmployeeMarketAlert.period_month_for,
      status: "draft",
      email_body: {}
    )

    expect { described_class.call(alert: alert) }.to raise_error(ArgumentError, /Stub/)
    expect(alert.reload.status).to eq("failed")
  end
end
