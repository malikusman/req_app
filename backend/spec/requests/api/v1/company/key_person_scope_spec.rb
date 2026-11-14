# frozen_string_literal: true

require "rails_helper"

# The scope card in the key user's conversation (Doc 08 §13): departments, the
# counts that price Stage 1, and the people the key user mentioned.
RSpec.describe "Key user's scope card", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company, company_profile: { "org_departments" => %w[Sales Finance Warehouse] }) }
  let(:user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let(:headers) { auth_headers_for(user) }
  let!(:engagement) do
    create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: user,
                        planned_departments: [{ "name" => "Sales", "count" => 2 },
                                              { "name" => "Finance", "count" => "UNKNOWN" }])
  end
  let(:path) { "/api/v1/company/leadership" }
  let(:mentioned) do
    [{ "name" => "Omar", "role" => "Buyer", "department" => "Procurement", "reason" => "knows day-to-day buying",
       "evidence" => "t4" },
     { "name" => "Rania Saleh", "role" => "Head of Sales", "department" => "Sales", "reason" => "runs sales",
       "evidence" => "t6" }]
  end
  let(:session) { engagement.participants.find_by!(source: "KEY_USER").conversation_sessions.last }

  before do
    allow(Openai::Client).to receive(:new).and_return(KeyPersonFakeClient.scripted)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    KeyPerson::Kickoff.call(engagement)
    post "#{path}/consent", headers: headers
    session.update!(state: "SCOPE_AND_PARTICIPANTS",
                    state_snapshot: session.state_snapshot.merge("participants_mentioned" => mentioned))
  end

  it "shows the departments, the counts still needed, and the people mentioned" do
    get path, headers: headers

    scope = response.parsed_body["scope"]
    expect(scope).to include("editable" => true, "counts_known" => false)
    expect(scope["suggested_departments"]).to eq(%w[Sales Finance Warehouse])
    expect(scope["people_mentioned"].pluck("name", "index")).to eq([["Omar", 0], ["Rania Saleh", 1]])
    expect(scope["people_mentioned"].first).not_to have_key("evidence")
  end

  it "settles the counts, warns about people left in a dropped department, and hands over to pricing" do
    create(:engagement_participant, engagement: engagement, name: "Sam", department: "Finance")
    session.update!(state: "COMPLETE")

    patch "#{path}/scope", params: { departments: [{ name: "Sales", count: 3 }, { name: "Warehouse", count: "2" }] },
                           headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(engagement.reload.planned_departments).to eq([{ "name" => "Sales", "count" => 3 },
                                                         { "name" => "Warehouse", "count" => 2 }])
    expect(response.parsed_body["warnings"]).to eq(["Sam is planned in Finance, which is no longer taking part."])
    expect(engagement.status).to eq("STAGE_1_PRICING")
  end

  it "keeps the plan open until the conversation ends" do
    patch "#{path}/scope", params: { departments: [{ name: "Sales", count: 3 }] }, headers: headers, as: :json
    expect(engagement.reload).to have_attributes(planned_participant_count: 3, status: "KEY_PERSON_DISCOVERY")
  end

  it "refuses an empty plan, and any change once Stage 1 is being priced" do
    patch "#{path}/scope", params: { departments: [] }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    engagement.update!(status: "STAGE_1_PRICING")
    patch "#{path}/scope", params: { departments: [{ name: "Sales", count: 9 }] }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it "adds a mentioned manager to the plan and invites them" do
    perform_enqueued_jobs do
      post "#{path}/people", params: { index: 1, participant: { participant_type: "key_person", name: "Rania Saleh",
                                                                role_title: "Head of Sales", department: "Sales",
                                                                email: "Rania@Client.example" } },
                             headers: headers, as: :json
    end

    expect(response).to have_http_status(:created)
    rania = engagement.participants.find_by!(name: "Rania Saleh")
    expect(rania).to have_attributes(source: "KEY_PERSON_CONVERSATION", email: "rania@client.example",
                                     participation_status: "INVITED")
    expect(ActionMailer::Base.deliveries.map(&:to)).to include(["rania@client.example"])
    expect(response.parsed_body["scope"]["people_mentioned"].pluck("name")).to eq(["Omar"])
  end

  it "adds staff to the plan without inviting them yet" do
    post "#{path}/people", params: { index: 0, participant: { participant_type: "EMPLOYEE", name: "Omar",
                                                              department: "Procurement" } },
                           headers: headers, as: :json

    expect(engagement.participants.find_by!(name: "Omar")).to have_attributes(participation_status: "NOT_INVITED")
  end

  it "lets them set aside someone they mentioned" do
    post "#{path}/people/dismiss", params: { index: 0 }, headers: headers, as: :json
    expect(response.parsed_body["scope"]["people_mentioned"].pluck("name")).to eq(["Rania Saleh"])
  end
end
