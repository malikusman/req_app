# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::Reminders do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company, company_profile: { "country" => "United Arab Emirates" }) }
  let(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY") }
  let(:dubai) { ActiveSupport::TimeZone["Asia/Dubai"] }
  # Thursday 5 November 2026, mid-morning in Dubai.
  let(:invited_at) { dubai.local(2026, 11, 5, 10) }
  let!(:manager) do
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Rania",
                                    email: "rania@client.example", participation_status: "INVITED",
                                    invited_at: invited_at)
  end

  def run_at(*args)
    travel_to(dubai.local(*args)) { perform_enqueued_jobs { described_class.run } }
  end

  def mails = ActionMailer::Base.deliveries.select { |m| m.to == ["rania@client.example"] }

  before { ActionMailer::Base.deliveries.clear }

  it "reminds someone who hasn't started after two working days, then four, then stops" do
    run_at(2026, 11, 6, 10)  # Friday: one working day
    expect(mails).to be_empty

    run_at(2026, 11, 9, 10)  # Monday: two (the weekend doesn't count)
    expect(mails.size).to eq(1)
    expect(mails.last.body.to_s).to include("A quick reminder", "/leadership/")

    run_at(2026, 11, 10, 10) # Tuesday: three
    expect(mails.size).to eq(1)

    run_at(2026, 11, 11, 10) # Wednesday: four
    expect(mails.size).to eq(2)
    expect(mails.last.body.to_s).to include("still waiting")

    run_at(2026, 11, 18, 10)
    expect(mails.size).to eq(2)
    expect(manager.reload.reminder_count).to eq(2)
  end

  it "refreshes the link with each reminder" do
    old = KeyPerson::Invite.new(manager).link![%r{/leadership/(.+)\z}, 1]
    run_at(2026, 11, 9, 10)

    expect(KeyPerson::Invite.participant_for(old)).to be_nil
    expect(KeyPerson::Invite.participant_for(mails.last.body.to_s[%r{/leadership/([\w-]+)}, 1])).to eq(manager)
  end

  it "never sends at night or at the weekend, by the company's own calendar" do
    run_at(2026, 11, 9, 22)  # Monday night
    run_at(2026, 11, 14, 11) # Saturday
    expect(mails).to be_empty

    company.update!(company_profile: { "country" => "Saudi Arabia" })
    travel_to(ActiveSupport::TimeZone["Asia/Riyadh"].local(2026, 11, 13, 11)) { described_class.run } # Friday
    expect(manager.reload.reminder_count).to eq(0)
  end

  it "nudges a paused conversation once, a working day later" do
    manager.update!(participation_status: "PAUSED")
    create(:conversation_session, participant: manager, state: "PAUSED", last_activity_at: invited_at)

    run_at(2026, 11, 6, 11)
    run_at(2026, 11, 6, 15)
    expect(mails.map { |m| m.body.to_s }).to contain_exactly(include("Pick up where you left off"))
  end

  it "reminds once about documents asked for and not received" do
    manager.update!(participation_status: "COMPLETED")
    session = create(:conversation_session, participant: manager, state: "COMPLETE")
    travel_to(invited_at) do
      DocumentRequest.create!(company: company, session: session, requested_item: "weekly sales pack", reason: "x")
    end

    manager.update!(participation_status: "STARTED")
    run_at(2026, 11, 9, 10)
    run_at(2026, 11, 10, 10)

    expect(mails.size).to eq(1)
    expect(mails.last.body.to_s).to include("weekly sales pack")
  end

  it "leaves people who finished or declined alone" do
    manager.update!(participation_status: "DECLINED")
    run_at(2026, 11, 11, 10)
    expect(mails).to be_empty
  end

  describe "the hourly sweep" do
    it "counts a conversation left for two hours as paused" do
      session = create(:conversation_session, participant: manager, state: "BROAD_DISCOVERY",
                                              last_activity_at: 3.hours.ago,
                                              state_snapshot: { "instruction" => { "mode" => "QUESTION",
                                                                                   "target_domain" => "CONCERNS" } })
      KeyPersonSweepJob.perform_now

      expect(session.reload.state).to eq("PAUSED")
      expect(session.state_snapshot["paused_instruction"]).to include("target_domain" => "CONCERNS")
      expect(session.turns).to be_empty
      expect(manager.reload.participation_status).to eq("PAUSED")
    end
  end
end
