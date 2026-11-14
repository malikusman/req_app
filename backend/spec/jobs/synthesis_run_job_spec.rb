# frozen_string_literal: true

require "rails_helper"

# Doc 10 §19, §23: new evidence asks for a run in the background; a burst of
# evidence makes one run, not several; and the hooks after interviews and
# leadership conversations ask for it.
RSpec.describe SynthesisRunJob do
  let(:company) { create(:company, :onboarded) }
  let!(:engagement) { create(:engagement, company: company) }

  it "joins evidence that arrives close together into one queued run" do
    first = described_class.request(engagement, trigger: "FINDINGS")
    second = described_class.request(engagement, trigger: "LEADERSHIP")

    expect(second).to eq(first)
    expect(SynthesisRun.where(engagement: engagement).count).to eq(1)
    expect(first.reload.counts["triggers"]).to eq(%w[FINDINGS LEADERSHIP])
    expect(enqueued_jobs.size).to eq(2)
  end

  it "runs only for the latest request" do
    run = described_class.request(engagement, trigger: "FINDINGS")
    allow(Synthesis::Run).to receive(:call)

    run.update!(requested_at: 2.minutes.ago)
    described_class.perform_now(run.id, 600)
    expect(Synthesis::Run).not_to have_received(:call)

    run.update!(requested_at: 11.minutes.ago)
    described_class.perform_now(run.id, 600)
    expect(Synthesis::Run).to have_received(:call).with(run)
  end

  it "runs a consultant's request straight away" do
    run = described_class.request(engagement, trigger: "MANUAL", wait: 0)
    allow(Synthesis::Run).to receive(:call)

    described_class.perform_now(run.id, 0)
    expect(Synthesis::Run).to have_received(:call).with(run)
  end

  it "does nothing without an engagement" do
    expect(described_class.request(nil, trigger: "FINDINGS")).to be_nil
  end

  it "is asked for once an interview's findings are drafted" do
    finding = synthesis_finding(company: company, role: "Clerk")
    allow(Findings::DraftCauseAndDirection).to receive(:call)

    DraftFindingCausesJob.perform_now([finding.id])
    expect(SynthesisRun.find_by(engagement: engagement)).to have_attributes(status: "QUEUED", trigger: "FINDINGS")
  end

  it "is asked for once a leadership context is built" do
    session = create(:conversation_session, participant: create(:engagement_participant, engagement: engagement,
                                                                                         participant_type: "KEY_PERSON"),
                                            state: "COMPLETE")
    allow(KeyPerson::ContextBuilder).to receive(:call)

    KeyPersonContextJob.perform_now(session.id)
    expect(SynthesisRun.find_by(engagement: engagement)).to have_attributes(status: "QUEUED", trigger: "LEADERSHIP")
  end
end
