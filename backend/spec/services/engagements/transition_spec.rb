# frozen_string_literal: true

require "rails_helper"

RSpec.describe Engagements::Transition do
  let(:company) { create(:company) }
  let(:key_user) { create(:company_user, company: company) }
  let(:engagement) { create(:engagement, company: company, status: "SET_UP", key_user: key_user) }

  def move(to, **opts)
    described_class.call(engagement: engagement, to: to, **opts)
  end

  it "moves along the normal path and records who moved it" do
    move("ONBOARDING", actor: key_user)

    expect(engagement.reload.status).to eq("ONBOARDING")
    expect(engagement.status_history.last).to include("from" => "SET_UP", "to" => "ONBOARDING",
                                                      "by_type" => "CompanyUser", "by_id" => key_user.id)
  end

  it "refuses a step the path doesn't allow" do
    expect { move("STAGE_1_ACTIVE", actor: key_user) }.to raise_error(described_class::Error)
    expect(engagement.reload.status).to eq("SET_UP")
  end

  it "does nothing when the engagement is already there" do
    move("SET_UP")
    expect(engagement.reload.status_history).to eq([])
  end

  describe "handing onboarding over" do
    before { engagement.update!(status: "ONBOARDING") }

    it "needs the confidentiality acknowledgement" do
      engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 2 }])
      expect { move("KEY_PERSON_DISCOVERY") }.to raise_error(described_class::Error, /confidentiality/)
    end

    it "needs at least one planned department" do
      engagement.update!(confidentiality_acknowledged_at: Time.current)
      expect { move("KEY_PERSON_DISCOVERY") }.to raise_error(described_class::Error, /department/)
    end

    it "goes ahead once both are there" do
      engagement.update!(confidentiality_acknowledged_at: Time.current,
                         planned_departments: [{ "name" => "Sales", "count" => 2 }])
      move("KEY_PERSON_DISCOVERY", actor: key_user)
      expect(engagement.reload.status).to eq("KEY_PERSON_DISCOVERY")
    end
  end

  describe "handing over to Stage 1 pricing" do
    let(:own) do
      create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", source: "KEY_USER",
                                      company_user: key_user, name: "Key user")
    end

    before do
      engagement.update!(status: "KEY_PERSON_DISCOVERY")
      create(:conversation_session, participant: own, state: "COMPLETE")
    end

    it "waits for the key user's own conversation to finish" do
      own.conversation_sessions.last.update!(state: "PRIORITY_CONFIRMATION")
      engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 2 }])
      expect { move("STAGE_1_PRICING") }.to raise_error(described_class::Error, /isn't finished/)
    end

    it "waits while any department's count is still unknown" do
      engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 2 },
                                               { "name" => "Finance", "count" => "UNKNOWN" }])
      expect { move("STAGE_1_PRICING") }.to raise_error(described_class::Error, /number of people/)
      expect(engagement.reload.status).to eq("KEY_PERSON_DISCOVERY")
    end

    it "goes ahead once every count is known" do
      engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 2 }])
      move("STAGE_1_PRICING", actor: key_user)
      expect(engagement.reload.status).to eq("STAGE_1_PRICING")
      expect(engagement.status_history.last).to include("from" => "KEY_PERSON_DISCOVERY", "to" => "STAGE_1_PRICING")
    end

    # Two hand-overs at once — the key user finishing as a consultant settles the
    # counts — each pass the checks; only the first may record the move.
    it "records the move once when two callers make it at the same time" do
      engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 2 }])
      stale = Engagement.find(engagement.id)
      move("STAGE_1_PRICING", actor: key_user)

      described_class.call(engagement: stale, to: "STAGE_1_PRICING", actor: key_user)

      expect(engagement.reload.status_history.count { |h| h["to"] == "STAGE_1_PRICING" }).to eq(1)
    end

    it "lets a Mjadi user move it on regardless, with a reason" do
      move("STAGE_1_PRICING", actor: create(:platform_user), reason: "Counts agreed by phone", force: true)
      expect(engagement.reload.status).to eq("STAGE_1_PRICING")
    end
  end

  describe "leaving Stage 1 pricing" do
    before do
      Pricing::Defaults.ensure!
      engagement.update!(status: "STAGE_1_PRICING")
    end

    it "starts Stage 1 only once the client has accepted a quote" do
      expect { move("STAGE_1_ACTIVE", actor: key_user) }.to raise_error(described_class::Error, /hasn't accepted/)

      create(:quote, :issued, engagement: engagement).update!(status: "ACCEPTED", accepted_by: key_user,
                                                              accepted_at: Time.current)
      move("STAGE_1_ACTIVE", actor: key_user)
      expect(engagement.reload.status).to eq("STAGE_1_ACTIVE")
    end

    it "closes only by Mjadi, with a reason" do
      expect { move("CLOSED", actor: key_user, reason: "No budget") }.to raise_error(described_class::Error, /Only Mjadi/)
      expect { move("CLOSED", actor: create(:platform_user)) }.to raise_error(described_class::Error, /Only Mjadi/)

      move("CLOSED", actor: create(:platform_user), reason: "Client declined the proposal")
      expect(engagement.reload.status).to eq("CLOSED")
    end
  end

  describe "forcing a move" do
    let(:admin) { create(:platform_user) }

    it "lets a Mjadi user close an engagement with a reason, and audits it" do
      expect { move("CLOSED", actor: admin, reason: "Client paused the work", force: true) }
        .to change(PlatformAuditLog, :count).by(1)

      expect(engagement.reload.status).to eq("CLOSED")
      expect(engagement.status_history.last).to include("reason" => "Client paused the work", "forced" => true)
    end

    it "needs a reason" do
      expect { move("CLOSED", actor: admin, force: true) }.to raise_error(described_class::Error)
    end

    it "is not open to the client" do
      expect { move("CLOSED", actor: key_user, reason: "Done", force: true) }.to raise_error(described_class::Error)
    end
  end
end
