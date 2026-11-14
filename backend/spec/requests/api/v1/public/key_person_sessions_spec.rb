# frozen_string_literal: true

require "rails_helper"

# Another manager's conversation with leadership, by their signed link (Doc 14 §4.3).
RSpec.describe "A manager's conversation with leadership", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:key_user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let!(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: key_user) }
  let!(:manager) do
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Rania Saleh",
                                    role_title: "Head of Sales", scope: "Sales, UAE", email: "rania@client.example")
  end
  let(:client) { KeyPersonFakeClient.scripted }

  before do
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  # The link from the invitation email.
  def invited_token
    perform_enqueued_jobs { KeyPerson::Kickoff.call(engagement) }
    mail = ActionMailer::Base.deliveries.find { |m| m.to == ["rania@client.example"] }
    mail.body.to_s[%r{/leadership/([\w-]+)}, 1]
  end

  it "invites the manager with a link of their own, in a mail that never mentions automation" do
    token = invited_token
    mail = ActionMailer::Base.deliveries.find { |m| m.to == ["rania@client.example"] }

    expect(token).to be_present
    expect(mail.body.to_s).to include("Layla Haddad suggested we speak with you", "Sales, UAE")
    expect(mail.body.to_s).not_to match(/automat|assess|consultant|AI\b/i)
    expect(manager.reload).to have_attributes(participation_status: "INVITED", persona: "SALES_COMMERCIAL")
    expect(manager.access_token_digest).to eq(KeyPerson::Invite.digest(token))
  end

  it "lets them hold their own conversation by that link" do
    token = invited_token
    path = "/api/v1/public/leadership/#{token}"

    get path
    expect(response.parsed_body["participant"]).to include("name" => "Rania Saleh", "key_user" => false)

    post "#{path}/consent"
    post "#{path}/messages", params: { text: "Yes, go ahead." }, as: :json
    expect(response).to have_http_status(:ok)
    expect(manager.conversation_sessions.last.turns.count).to eq(3)
  end

  it "never shows them the key user's conversation" do
    token = invited_token
    own = engagement.participants.find_by!(source: "KEY_USER")
    session = create(:conversation_session, participant: own, state: "BROAD_DISCOVERY")
    create(:conversation_turn, session: session, turn_index: 1, text: "SENTINEL-KEY-USER-ANSWER")

    get "/api/v1/public/leadership/#{token}"
    expect(response.body).not_to include("SENTINEL-KEY-USER-ANSWER")
  end

  it "refuses a link that is wrong, expired, or has been replaced" do
    token = invited_token

    get "/api/v1/public/leadership/not-a-token"
    expect(response).to have_http_status(:unauthorized)

    KeyPerson::Invite.call(manager.reload)
    get "/api/v1/public/leadership/#{token}"
    expect(response).to have_http_status(:unauthorized)

    manager.update!(access_token_digest: KeyPerson::Invite.digest("fresh"), access_token_expires_at: 1.minute.ago)
    get "/api/v1/public/leadership/fresh"
    expect(response).to have_http_status(:unauthorized)
  end

  it "never lets a manager's answers change the company's facts" do
    allow(Openai::Client).to receive(:new).and_return(
      KeyPersonFakeClient.scripted do |capture, _context, turn_id|
        capture.merge("profile_facts_discovered" => [{ "field" => "locations", "value" => "Qatar", "evidence" => turn_id }])
      end
    )
    path = "/api/v1/public/leadership/#{invited_token}"
    post "#{path}/consent"
    post "#{path}/messages", params: { text: "We also have a team in Qatar." }, as: :json

    expect(company.reload.company_profile["locations"]).to be_nil
  end
end
