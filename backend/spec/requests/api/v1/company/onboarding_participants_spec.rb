# frozen_string_literal: true

require "rails_helper"

# Participant planning, P3 and P4 (Doc 07 §7).
RSpec.describe "Onboarding participant planning", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }
  let!(:engagement) { create(:engagement, company: company, status: "ONBOARDING", key_user: user) }
  let(:path) { "/api/v1/company/onboarding/participants" }

  def add(attrs)
    post path, params: { participant: attrs }, headers: headers, as: :json
  end

  it "records staff the key user names, and managers to speak with, as nominated by the client" do
    add(participant_type: "employee", name: "Omar Haddad", role_title: "Buyer", department: "Procurement",
        phone_e164: "+971 50 111 2222", email: "Omar@Client.example")
    add(participant_type: "KEY_PERSON", name: "Rania Saleh", role_title: "Head of Sales", scope: "Sales, UAE")

    expect(response).to have_http_status(:created)
    staff, manager = engagement.participants.order(:id)
    expect(staff).to have_attributes(participant_type: "EMPLOYEE", phone_e164: "+971501112222",
                                     email: "omar@client.example", nominated_by_client: true, employee_id: nil)
    expect(manager).to have_attributes(participant_type: "KEY_PERSON", scope: "Sales, UAE")
  end

  it "needs a name, and refuses the same phone twice" do
    add(participant_type: "EMPLOYEE", name: "")
    expect(response).to have_http_status(:unprocessable_entity)

    add(participant_type: "EMPLOYEE", name: "A", phone_e164: "+971500000001")
    add(participant_type: "EMPLOYEE", name: "B", phone_e164: "+971500000001")
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "warns when the phone already belongs to another client's participant" do
    create(:employee, company: create(:company), phone_e164: "+971500000002")
    add(participant_type: "EMPLOYEE", name: "Sam", phone_e164: "+971500000002")

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["warnings"].first).to match(/another company/)
  end

  it "lists, edits and removes only this engagement's people" do
    other = create(:engagement_participant, engagement: create(:engagement))
    add(participant_type: "EMPLOYEE", name: "Lina")
    mine = engagement.participants.last

    get path, headers: headers
    expect(JSON.parse(response.body)["participants"].map { |p| p["id"] }).to eq([mine.id])

    patch "#{path}/#{mine.id}", params: { participant: { role_title: "Accountant", participant_type: "KEY_PERSON" } },
                                headers: headers, as: :json
    expect(mine.reload).to have_attributes(role_title: "Accountant", participant_type: "EMPLOYEE")

    delete "#{path}/#{other.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    delete "#{path}/#{mine.id}", headers: headers
    expect(response).to have_http_status(:no_content)
  end

  it "links a planned person to the employee once they are invited" do
    add(participant_type: "EMPLOYEE", name: "Omar Haddad", phone_e164: "+971501112222")
    planned = engagement.participants.last

    post "/api/v1/company/employees",
         params: { phone_e164: "+971501112222", display_name: "Omar Haddad", engagement_participant_id: planned.id,
                   send_whatsapp: false },
         headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(planned.reload.employee).to eq(Employee.find_by(phone_e164: "+971501112222"))
  end
end
