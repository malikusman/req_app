# frozen_string_literal: true

require "rails_helper"

# The dashboard during the conversations with leadership: the key user's own,
# and the other managers' status — never what anyone said (Doc 14 §9.2).
RSpec.describe "Company dashboard, leadership stage", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let!(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: user) }

  before do
    stub_request(:get, %r{http://gotenberg:3000/health}).to_return(status: 200, body: "")
    allow(Openai::Client).to receive(:new).and_return(KeyPersonFakeClient.scripted)
    manager = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Rania Saleh",
                                              role_title: "Head of Sales", email: "rania@client.example")
    KeyPerson::Kickoff.call(engagement)
    session = create(:conversation_session, participant: manager.reload, state: "BROAD_DISCOVERY")
    create(:conversation_turn, session: session, turn_index: 1, text: "SENTINEL-MANAGER-ANSWER")
    manager.update!(participation_status: "STARTED")
  end

  it "shows the key user their own conversation and the managers' status only" do
    get "/api/v1/company/dashboard", headers: auth_headers_for(user)

    leadership = response.parsed_body["leadership"]
    expect(leadership).to include("available" => true, "is_key_user" => true)
    expect(leadership["own"]).to eq("participation_status" => "INVITED", "finished" => false)
    expect(leadership["managers"]).to eq([{ "id" => engagement.participants.find_by!(name: "Rania Saleh").id,
                                            "name" => "Rania Saleh", "role_title" => "Head of Sales",
                                            "participation_status" => "STARTED", "can_invite" => true,
                                            "reminders_used_up" => false }])
    expect(response.body).not_to include("SENTINEL-MANAGER-ANSWER")
  end
end
