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
