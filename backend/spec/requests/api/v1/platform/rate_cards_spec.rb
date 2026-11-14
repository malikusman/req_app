# frozen_string_literal: true

require "rails_helper"

# The Stage 1 rate card and the margin floor (Doc 17 §7–8, Doc 21 §27): any
# platform user sees them and their history; only a super admin makes a new
# version, always with a reason; quotes keep the version they were made with.
RSpec.describe "Platform: rate card and margin floor", type: :request do
  let(:admin) { create(:platform_user, role: "super_admin", name: "Sara Admin") }
  let(:analyst) { create(:platform_user, role: "analyst") }

  before { Pricing::Defaults.ensure! }

  def body = JSON.parse(response.body)

  def form(**overrides)
    stage1 = Pricing::Defaults::STAGE1_V1.deep_dup.merge("base_fee" => 20_000, "tax_rates" => { "AE" => 0.05, "SA" => 0.15 })
    { stage1: stage1, consultant_internal_cost: 275, consultant_charge_rate: 800, currency: "AED",
      reason: "Agreed with Masood and Usman (K2)" }.merge(overrides)
  end

  it "shows the rates in effect and every version, to any platform user" do
    get "/api/v1/platform/rate_card", headers: auth_headers_for(analyst)

    expect(response).to have_http_status(:ok)
    expect(body["rate_card"]).to include("placeholder" => true, "consultant_internal_cost" => 250)
    expect(body["rate_card"]["stage1"]).to include("base_fee" => 18_000)
    expect(body["margin_floor"]).to include("percent" => "60.0")
    expect(body["can_act"]).to be(false)
  end

  it "lets only a super admin make a new version" do
    post "/api/v1/platform/rate_card", params: form, headers: auth_headers_for(analyst), as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/platform/margin_floor", params: { percent: 50, reason: "x" }, headers: auth_headers_for(analyst), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "makes a new rate card version with who and why, keeping the other rates, and audits it" do
    expect { post "/api/v1/platform/rate_card", params: form, headers: auth_headers_for(admin), as: :json }
      .to change(PlatformAuditLog.where(action: "rate_card_version_created"), :count).by(1)

    expect(response).to have_http_status(:created)
    current = RateCardVersion.current
    expect(current).to have_attributes(version: 2, placeholder: false, changed_by: admin,
                                       reason: "Agreed with Masood and Usman (K2)")
    expect(current.stage1).to include("base_fee" => 20_000, "tax_rates" => { "AE" => 0.05, "SA" => 0.15 })
    expect(current.rates.dig("consultant", "mjadi_team")).to eq("internal_cost" => 275, "charge_rate" => 800)
    expect(body["rate_cards"].map { |r| r["version"] }).to eq([2, 1])
  end

  it "keeps only the formula's values, as numbers" do
    stage1 = form[:stage1].merge("base_fee" => "19500", "surprise" => "drop me")
    post "/api/v1/platform/rate_card", params: form(stage1: stage1), headers: auth_headers_for(admin), as: :json

    expect(RateCardVersion.current.stage1).to include("base_fee" => 19_500)
    expect(RateCardVersion.current.stage1).not_to have_key("surprise")
  end

  it "refuses a version without a reason, a missing value or an impossible one, and keeps the old" do
    post "/api/v1/platform/rate_card", params: form(reason: " "), headers: auth_headers_for(admin), as: :json
    expect(body["error"]).to eq("Say why the rates are changing")

    stage1 = form[:stage1].tap { |s| s.delete("licences") }
    post "/api/v1/platform/rate_card", params: form(stage1: stage1), headers: auth_headers_for(admin), as: :json
    expect(body["error"]).to include("licences")

    stage1 = form[:stage1].merge("deep_dives" => { "min" => 6, "max" => 3 }, "tax_rates" => { "AE" => 5 })
    post "/api/v1/platform/rate_card", params: form(stage1: stage1), headers: auth_headers_for(admin), as: :json
    expect(body["error"]).to include("fewest deep dives", "below 100%")

    expect(RateCardVersion.current.version).to eq(1)
  end

  it "makes a new margin floor version with a reason, and audits it" do
    post "/api/v1/platform/margin_floor", params: { percent: 55 }, headers: auth_headers_for(admin), as: :json
    expect(body["error"]).to eq("Say why the floor is changing")

    expect do
      post "/api/v1/platform/margin_floor", params: { percent: 55, reason: "Pilot year" },
                                            headers: auth_headers_for(admin), as: :json
    end.to change(PlatformAuditLog.where(action: "margin_floor_changed"), :count).by(1)
    expect(MarginFloorVersion.current).to have_attributes(value: BigDecimal("0.55"), changed_by: admin)
    expect(body["margin_floors"].first).to include("percent" => "55.0", "reason" => "Pilot year")

    post "/api/v1/platform/margin_floor", params: { percent: 120, reason: "x" }, headers: auth_headers_for(admin), as: :json
    expect(body["error"]).to eq("The floor must be between 0 and 100%")
  end

  describe "quotes made on an earlier version" do
    let(:engagement) do
      create(:engagement, status: "STAGE_1_PRICING", languages: %w[en],
                          planned_departments: [{ "name" => "Sales", "count" => 3 }])
    end
    let!(:quote) { Pricing::ProposeStage1.call(engagement).quote }

    before { post "/api/v1/platform/rate_card", params: form, headers: auth_headers_for(admin), as: :json }

    it "keep it, are counted, and can be recalculated on the new one" do
      expect(quote.reload.rate_card_version.version).to eq(1)
      expect(body["waiting_on_older_rates"]).to eq(1)

      post "/api/v1/platform/engagements/#{engagement.id}/stage1_quote", headers: auth_headers_for(admin)
      fresh = engagement.reload.open_stage1_quote
      expect(fresh).to have_attributes(version: 2, subtotal: BigDecimal("29750")) # 20,000 + 3 × 1,500 + 3 × 1,750
      expect(fresh.rate_card_version.version).to eq(2)
      expect(quote.reload.status).to eq("SUPERSEDED")
    end

    it "aren't recalculated once they are with the client" do
      Pricing::Review.new(actor: admin).approve(quote)
      post "/api/v1/platform/engagements/#{engagement.id}/stage1_quote", headers: auth_headers_for(admin)

      expect(body["error"]).to eq("This engagement's quote is with the client")
      expect(quote.reload.status).to eq("ISSUED")
    end
  end
end
