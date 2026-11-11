# frozen_string_literal: true

require "rails_helper"

# The platform proposes the Stage 1 quote when an engagement reaches pricing,
# and again when what it is calculated from changes; the administrators are
# told (Doc 17 §1, §2, §17; Doc 21 §42).
RSpec.describe Pricing::ProposeStage1 do
  include ActiveJob::TestHelper

  let(:company) { create(:company, company_profile: { "country" => "UAE", "locations" => ["Dubai"] }) }
  let(:key_user) { create(:company_user, company: company) }
  let(:engagement) do
    create(:engagement, company: company, key_user: key_user, status: "STAGE_1_PRICING", languages: %w[en ar],
                        planned_departments: [{ "name" => "Sales", "count" => 3 }, { "name" => "Finance", "count" => 2 }])
  end

  before { Pricing::Defaults.ensure! }

  it "starts when the engagement is handed over to pricing" do
    engagement.update!(status: "KEY_PERSON_DISCOVERY")
    own = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", source: "KEY_USER",
                                          company_user: key_user, name: "Key user")
    create(:conversation_session, participant: own, state: "COMPLETE")

    expect { Engagements::Transition.call(engagement: engagement, to: "STAGE_1_PRICING", actor: key_user) }
      .to have_enqueued_job(ProposeStage1Job).with(engagement.id)
  end

  it "proposes a quote from the plan, with the template scope statement, and tells the approvers" do
    create(:platform_user, role: "analyst")
    approver = create(:platform_user)

    result = nil
    expect { result = described_class.call(engagement) }
      .to have_enqueued_mail(PricingMailer, :quote_awaiting_approval)

    quote = result.quote
    expect(quote).to have_attributes(status: "PROPOSED", version: 1, participants_included: 5, deep_dives_included: 5,
                                     currency: "AED", explanation_source: "TEMPLATE", below_floor: false)
    expect(quote.subtotal).to eq(BigDecimal("35250")) # 18,000 + 5 × 1,500 + 5 × 1,750 + 1,000 for Arabic
    expect(quote.line_items.map { |l| l["key"] }).to eq(%w[base participants deep_dives complexity])
    expect(quote.client_scope["additional_participants"]).to include("AED 1,500")
    expect(quote.events.map(&:event)).to eq(["proposed"])

    mail = PricingMailer.quote_awaiting_approval(quote)
    expect(mail.to).to eq([approver.email])
    expect(mail.body.encoded).to include("/platform/pricing/#{quote.id}")
  end

  it "flags a quote below the margin floor in the subject" do
    create(:margin_floor_version, value: BigDecimal("0.95"), reason: "Test: an unreachable floor")
    quote = described_class.call(engagement).quote

    expect(quote.below_floor).to be(true)
    expect(PricingMailer.quote_awaiting_approval(quote).subject).to start_with("Below margin floor")
  end

  it "returns the open quote when nothing has changed" do
    first = described_class.call(engagement).quote

    expect { expect(described_class.call(engagement).quote).to eq(first) }
      .not_to have_enqueued_mail(PricingMailer, :quote_awaiting_approval)
    expect(engagement.quotes.count).to eq(1)
  end

  it "supersedes the open quote when the plan changes, keeping the administrator's corrections" do
    first = described_class.call(engagement, actor: create(:platform_user), adjustments: { "locations" => 2 }).quote
    engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 6 }])

    second = described_class.call(engagement, reason: "Plan changed").quote

    expect(first.reload.status).to eq("SUPERSEDED")
    expect(first.events.last).to have_attributes(event: "superseded", detail: { "reason" => "Plan changed" })
    expect(second).to have_attributes(version: 2, parent_quote: first, participants_included: 6)
    expect(second.inputs).to include("locations" => 2)
  end

  it "doesn't tell the administrators about a quote one of them just made" do
    expect { described_class.call(engagement, actor: create(:platform_user)) }
      .not_to have_enqueued_mail(PricingMailer, :quote_awaiting_approval)
  end

  it "stops, and tells the administrators, when the rate card has no tax rate for the client's country" do
    company.update!(company_profile: { "country" => "Saudi Arabia" })

    result = nil
    expect { result = described_class.call(engagement) }.to have_enqueued_mail(PricingMailer, :pricing_blocked)
    expect(result.error).to include("tax rate for SA")
    expect(engagement.quotes).to be_empty
  end

  it "won't price an engagement that isn't being priced, or was already accepted" do
    engagement.update!(status: "KEY_PERSON_DISCOVERY")
    expect(described_class.call(engagement).error).to include("isn't being priced")

    engagement.update!(status: "STAGE_1_PRICING")
    accepted = create(:quote, :issued, engagement: engagement)
    accepted.update!(status: "ACCEPTED", accepted_by: key_user, accepted_at: Time.current)
    expect(described_class.call(engagement).error).to include("already accepted")
  end

  describe "a consultant changing the plan while it is being priced", type: :request do
    let(:consultant) { create(:consultant_user) }

    before do
      create(:consultant_assignment, consultant_user: consultant, company: company, status: "active")
      described_class.call(engagement)
    end

    it "makes a fresh quote" do
      patch "/api/v1/consultant/companies/#{company.id}/leadership/plan",
            params: { departments: [{ name: "Sales", count: 7 }] }, headers: auth_headers_for(consultant), as: :json

      expect(response).to have_http_status(:ok)
      expect(engagement.reload.open_stage1_quote).to have_attributes(version: 2, participants_included: 7)
      expect(engagement.quotes.find_by(version: 1).status).to eq("SUPERSEDED")
    end
  end
end
