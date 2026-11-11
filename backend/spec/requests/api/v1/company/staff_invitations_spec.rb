# frozen_string_literal: true

require "rails_helper"

# Staff are invited once the client has accepted the Stage 1 price (Doc 14
# §4.1), and anyone beyond what it covers only with the client's confirmation,
# flagged for the additional-participant charge (Doc 06 §3.6, Doc 17 §12).
RSpec.describe "Company: inviting staff around the Stage 1 price", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:key_user) { create(:company_user, company: company, role: "company_admin") }
  let(:headers) { auth_headers_for(key_user) }
  let!(:engagement) do
    create(:engagement, company: company, key_user: key_user, status: "STAGE_1_PRICING", created_at: 1.week.ago,
                        planned_departments: [{ "name" => "Sales", "count" => 2 }])
  end

  def invite(phone, **extra)
    post "/api/v1/company/employees", params: { phone_e164: phone, display_name: "Person #{phone[-2..]}", **extra },
                                      headers: headers, as: :json
  end

  def bulk(rows, **extra)
    post "/api/v1/company/employees/bulk_create", params: { employees: rows, **extra }, headers: headers, as: :json
  end

  def body = JSON.parse(response.body)

  def accept_price!(participants: 2)
    Pricing::Defaults.ensure!
    quote = create(:quote, :issued, engagement: engagement, participants_included: participants)
    quote.update!(status: "ACCEPTED", accepted_by: key_user, accepted_at: Time.current)
    engagement.update!(status: "STAGE_1_ACTIVE")
    quote
  end

  it "won't invite anyone, singly or in bulk, before the price is accepted" do
    expect { invite("+971500000001") }.not_to change(Employee, :count)
    expect(response).to have_http_status(:conflict)
    expect(body).to include("code" => "invitations_locked",
                            "error" => "Your team can be invited once the Stage 1 proposal is accepted.")

    expect { bulk([{ phone_e164: "+971500000001" }, { phone_e164: "+971500000002" }]) }.not_to change(Employee, :count)
    expect(response).to have_http_status(:conflict)

    get "/api/v1/company/employees", headers: headers
    expect(body["invitations"]).to include("open" => false)
  end

  it "leaves a company from before engagements alone" do
    engagement.destroy!
    invite("+971500000001")
    expect(response).to have_http_status(:created)
  end

  describe "once the price is accepted" do
    before { accept_price!(participants: 2) }

    it "invites up to the number covered, then asks before inviting someone extra, and flags them" do
      invite("+971500000001")
      invite("+971500000002")
      expect(response).to have_http_status(:created)
      expect(body["additional"]).to be(false)

      expect { invite("+971500000003") }.not_to change(Employee, :count)
      expect(response).to have_http_status(:conflict)
      expect(body).to include("code" => "confirm_additional", "included" => 2, "invited" => 2, "extra" => 1,
                              "rate" => "1500.0", "currency" => "AED")
      expect(body["error"]).to include("AED 1,500")

      invite("+971500000003", confirm_additional: true)
      expect(response).to have_http_status(:created)
      expect(body["additional"]).to be(true)
      extra = engagement.participants.find_by!(added_after_pricing: true)
      expect(extra).to have_attributes(source: "INVITED", participant_type: "EMPLOYEE", name: "Person 03")

      expect(Pricing::AdditionalParticipants.for(engagement)).to include(count: 1, amount: "1500.0")
      get "/api/v1/company/stage1_quote", headers: headers
      expect(body.dig("quote", "additional_participants", "count")).to eq(1)
    end

    it "flags the planned row when the extra person was in the plan" do
      invite("+971500000001")
      invite("+971500000002")
      planned = create(:engagement_participant, engagement: engagement, name: "Planned later")

      invite("+971500000003", confirm_additional: true, engagement_participant_id: planned.id)
      expect(planned.reload).to have_attributes(added_after_pricing: true, employee: Employee.last)
    end

    it "doesn't count someone who declined, so a swap is free" do
      invite("+971500000001")
      invite("+971500000002")
      Employee.find_by!(phone_e164: "+971500000002").update!(participation_status: "declined")

      invite("+971500000003")
      expect(response).to have_http_status(:created)
      expect(body["additional"]).to be(false)
    end

    it "checks a bulk invitation as a whole before inviting anyone" do
      rows = [{ phone_e164: "+971500000001" }, { phone_e164: "+971500000002" }, { phone_e164: "+971500000003" }]
      expect { bulk(rows) }.not_to change(Employee, :count)
      expect(body).to include("code" => "confirm_additional", "adding" => 3, "extra" => 1)

      expect { bulk(rows.first(2) + [{ phone_e164: "+971500000001" }], confirm_additional: true) }
        .not_to change(Employee, :count)
      expect(body["errors"]).to eq(["Row 3: Phone appears twice in this list"])

      expect { bulk(rows, confirm_additional: true) }.to change(Employee, :count).by(3)
      expect(engagement.participants.where(added_after_pricing: true).count).to eq(1)
    end
  end

  it "flags another manager added once Stage 1 is being priced" do
    late = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Late manager")
    expect(late.added_after_pricing).to be(true)

    engagement.update!(status: "KEY_PERSON_DISCOVERY")
    early = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Early manager")
    expect(early.added_after_pricing).to be(false)
  end

  it "holds a queued WhatsApp invitation if the engagement isn't open to invitations" do
    accept_price!
    invite("+971500000001")
    invitation = EmployeeInvitation.last
    engagement.update!(status: "STAGE_1_PRICING")

    SendEmployeeInvitationJob.perform_now(invitation.id)
    expect(invitation.reload).to have_attributes(delivery_status: "failed",
                                                 error_message: "Held: the Stage 1 proposal isn't accepted")
  end
end
