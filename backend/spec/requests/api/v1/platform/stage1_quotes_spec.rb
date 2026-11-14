# frozen_string_literal: true

require "rails_helper"

# The administrator's review of a Stage 1 quote (Doc 17 §8–9, Doc 05 §10,
# Doc 21 §26): every platform user can look; only a super admin can approve,
# adjust, change inputs or send it back; the floor and the structured reasons
# hold; every action is kept.
RSpec.describe "Platform: Stage 1 quotes", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:platform_user, role: "super_admin", name: "Sara Admin") }
  let(:analyst) { create(:platform_user, role: "analyst") }
  let(:company) { create(:company, company_profile: { "country" => "UAE" }) }
  let(:consultant) { create(:consultant_user) }
  let(:engagement) do
    create(:engagement, company: company, status: "STAGE_1_PRICING", languages: %w[en], lead_consultant: consultant,
                        planned_departments: [{ "name" => "Sales", "count" => 4 }])
  end
  let(:quote) { Pricing::ProposeStage1.call(engagement).quote }
  let(:path) { "/api/v1/platform/stage1_quotes/#{quote.id}" }

  before { Pricing::Defaults.ensure! }

  def act(action, by: admin, **params)
    post "#{path}/#{action}", params: params, headers: auth_headers_for(by), as: :json
  end

  def body = JSON.parse(response.body)

  it "shows the queue and the derivation, margin and rate card to any platform user" do
    quote
    get "/api/v1/platform/stage1_quotes", headers: auth_headers_for(analyst)
    expect(body["quotes"].map { |q| q["id"] }).to eq([quote.id])
    expect(body["proposed_count"]).to eq(1)

    get path, headers: auth_headers_for(analyst)
    expect(body["quote"]).to include("margin_percent" => quote.margin_percent.to_s("F"), "below_floor" => false)
    expect(body["quote"]["internal"]).to include("cost", "total_hours")
    expect(body["rate_card"]).to include("placeholder" => true)
    expect(body["can_act"]).to be(false)
  end

  it "lets only a super admin act" do
    act(:approve, by: analyst)
    expect(response).to have_http_status(:forbidden)
    expect(quote.reload.status).to eq("PROPOSED")

    get path, headers: auth_headers_for(admin)
    expect(body["can_act"]).to be(true)
  end

  it "approves and issues the quote, valid for the rate card's period, and audits it" do
    expect { act(:approve) }.to change(PlatformAuditLog.where(action: "stage1_quote_issued"), :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(quote.reload).to have_attributes(status: "ISSUED", approved_by: admin, valid_until: Time.zone.today + 30)
    expect(quote.client_scope["validity"]).to include((Time.zone.today + 30).strftime("%-d %B %Y"))
    expect(quote.events.map(&:event)).to eq(%w[proposed issued])
  end

  describe "below the margin floor" do
    before { create(:margin_floor_version, value: BigDecimal("0.95"), reason: "Test: an unreachable floor") }

    it "can't be issued without an override and a structured reason" do
      act(:approve)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["error"]).to include("below the 95.0% margin floor")
      expect(quote.reload.status).to eq("PROPOSED")

      act(:approve, floor_override: { reason: "OTHER" })
      expect(body["error"]).to include("required when the reason is other")

      act(:approve, floor_override: { reason: "RELATIONSHIP" })
      expect(response).to have_http_status(:ok)
      expect(quote.reload.status).to eq("ISSUED")
      expect(quote.estimate_overrides.sole).to have_attributes(kind: "FLOOR_OVERRIDE", structured_reason: "RELATIONSHIP",
                                                               actor: admin)
      expect(quote.events.map(&:event)).to include("floor_overridden")
    end
  end

  describe "adjusting the price" do
    it "can't be saved without a structured reason" do
      act(:adjust, subtotal: 25_000)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["error"]).to include("Structured reason is required")
      expect(engagement.quotes.count).to eq(1)
    end

    it "makes a new version with an adjustment line, superseding the old one" do
      act(:adjust, subtotal: 25_000, reason: "COMPETITIVE")

      expect(response).to have_http_status(:ok)
      adjusted = engagement.quotes.find_by!(version: 2)
      expect(adjusted).to have_attributes(status: "PROPOSED", parent_quote: quote, subtotal: BigDecimal("25000"))
      expect(adjusted.line_items.last).to include("key" => "adjustment")
      expect(adjusted.estimate_overrides.sole).to have_attributes(kind: "ADJUST", structured_reason: "COMPETITIVE",
                                                                  original_total: quote.subtotal)
      expect(quote.reload.status).to eq("SUPERSEDED")
      expect(body["quote"]["id"]).to eq(adjusted.id)
    end

    it "won't change a quote the client is looking at, or an older version" do
      act(:approve)
      act(:adjust, subtotal: 25_000, reason: "COMPETITIVE")
      expect(body["error"]).to eq("This quote is with the client")
    end
  end

  it "recalculates with corrected inputs as a new version" do
    act(:change_inputs, deep_dives: 3, locations: 2)

    expect(response).to have_http_status(:ok)
    newer = engagement.quotes.find_by!(version: 2)
    expect(newer).to have_attributes(deep_dives_included: 3, status: "PROPOSED")
    expect(newer.inputs).to include("locations" => 2)
    expect(newer.events.first.event).to eq("inputs_changed")
    expect(quote.reload.status).to eq("SUPERSEDED")
  end

  it "rejects a non-number for the deep dives" do
    act(:change_inputs, deep_dives: "lots")
    expect(body["error"]).to eq("Deep dives must be a whole number")
  end

  it "sends a quote back with a note, and tells the lead consultant" do
    act(:reject)
    expect(body["error"]).to eq("Say why it is being sent back")

    expect { act(:reject, note: "Finance has one person; check with the client") }
      .to change(Notification.where(recipient: consultant), :count).by(1)
    expect(quote.reload).to have_attributes(status: "REJECTED", rejected_by: admin,
                                            rejection_note: "Finance has one person; check with the client")
  end

  it "calculates a quote for an engagement that reached pricing before quotes existed, and again after a rejection" do
    post "/api/v1/platform/engagements/#{engagement.id}/stage1_quote", headers: auth_headers_for(admin)
    expect(response).to have_http_status(:created)
    first = engagement.quotes.sole

    post "/api/v1/platform/stage1_quotes/#{first.id}/reject", params: { note: "Recheck" },
                                                               headers: auth_headers_for(admin), as: :json
    post "/api/v1/platform/engagements/#{engagement.id}/stage1_quote", headers: auth_headers_for(admin)
    expect(engagement.quotes.order(:version).pluck(:version, :status)).to eq([[1, "REJECTED"], [2, "PROPOSED"]])
  end
end
