# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::Kickoff do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:key_user) do
    create(:company_user, company: company, name: "Layla Haddad", email: "layla@client.example", job_title: "Owner",
                          preferred_language: "ar")
  end
  let(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: key_user) }

  def kick = perform_enqueued_jobs { described_class.call(engagement) }

  it "gives the key user a row of their own and tells them their conversation is ready" do
    kick

    own = engagement.participants.find_by!(source: "KEY_USER")
    expect(own).to have_attributes(participant_type: "KEY_PERSON", company_user: key_user, persona: "CEO_OWNER_MD",
                                   scope: "Company-wide", preferred_language: "ar", participation_status: "INVITED")
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(["layla@client.example"])
    expect(mail.body.to_s).to include("/company/leadership")
  end

  it "invites the other managers who have an email, and only once" do
    with_email = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON",
                                                 name: "Rania", email: "rania@client.example")
    without = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Omar")
    staff = create(:engagement_participant, engagement: engagement, participant_type: "EMPLOYEE", name: "Sam",
                                            email: "sam@client.example")

    kick
    kick

    expect(with_email.reload.participation_status).to eq("INVITED")
    expect(without.reload.participation_status).to eq("NOT_INVITED")
    expect(staff.reload.participation_status).to eq("NOT_INVITED")
    expect(ActionMailer::Base.deliveries.map(&:to).flatten.tally).to eq("layla@client.example" => 1,
                                                                       "rania@client.example" => 1)
  end

  it "takes over the key user's own entry when they listed themselves as a manager" do
    listed = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON",
                                             name: "Layla H.", email: "Layla@Client.example", role_title: "Owner")
    kick

    expect(listed.reload.source).to eq("KEY_USER")
    expect(engagement.participants.key_persons.count).to eq(1)
  end

  it "does nothing before onboarding is handed over" do
    engagement.update!(status: "ONBOARDING")
    kick
    expect(engagement.participants).to be_empty
  end
end
