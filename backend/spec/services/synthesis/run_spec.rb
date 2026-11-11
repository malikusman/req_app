# frozen_string_literal: true

require "rails_helper"

# Doc 10 §19 and §28: a run judges only new or changed pairs, keeps clusters
# and their keys when nothing changed, extends an existing cluster when a late
# interview joins it, leaves a consultant's clusters alone, notices when the
# evidence moves on, and a failure leaves the previous synthesis intact.
RSpec.describe Synthesis::Run do
  let(:company) { create(:company, :onboarded) }
  let(:engagement) { create(:engagement, company: company) }
  let(:client) { Synthesis::ScriptedClient.new }

  before { allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false) }

  def quote_finding(role: "Sales Coordinator", hours: [100, 150])
    synthesis_finding(company: company, role: role, title: "Preparing quotes",
                      what_happens_now: "Check stock and the price list, fill the quotation template, email the customer",
                      hours: hours)
  end

  def new_run(trigger: "MANUAL")
    SynthesisRun.create!(company: company, engagement: engagement, trigger: trigger, requested_at: Time.current,
                         version: (SynthesisRun.where(engagement: engagement).maximum(:version) || 0) + 1)
  end

  def run! = described_class.call(new_run, client: client)

  it "groups the same work described by two people and counts each person's own effort" do
    quote_finding(hours: [100, 150])
    quote_finding(hours: [80, 120])
    synthesis_finding(company: company, role: "Driver", department: "Logistics", title: "Deliveries",
                      what_happens_now: "Load the van and drive the route", hours: [400, 500])

    run = run!
    expect(run).to have_attributes(status: "COMPLETE")
    expect(run.counts).to include("work_items" => 3, "pairs_judged" => 1, "clusters" => 1)

    cluster = ProcessCluster.current.sole
    expect(cluster).to have_attributes(status: "PROVISIONAL", cluster_type: "SHARED_IDENTICAL", single_member: false)
    expect(cluster.effort_normalization).to have_attributes(raw_min: 180, raw_max: 270, dedup_min: 180, dedup_max: 270)
    expect(AiRun.where(stage: "P10", subject: run).count).to eq(1)
    expect(AiRun.where(stage: "P11", subject: run).count).to eq(1)
    expect(ConsultancyOpportunity.current.count).to eq(1)
  end

  it "judges nothing again and makes no new versions when nothing changed" do
    quote_finding
    quote_finding
    run!
    cluster = ProcessCluster.current.sole

    second = run!
    expect(second.counts["pairs_judged"]).to eq(0)
    expect(ProcessCluster.current.sole).to eq(cluster)
    expect(ProcessCluster.count).to eq(1)
    expect(ConsultancyOpportunity.count).to eq(1)
  end

  it "attaches a late interview to the existing cluster, keeping its key" do
    quote_finding
    quote_finding
    run!
    key = ProcessCluster.current.sole.cluster_key

    quote_finding(hours: [60, 90])
    run!
    cluster = ProcessCluster.current.sole
    expect(cluster).to have_attributes(cluster_key: key, version: 2)
    expect(cluster.members.size).to eq(3)
    expect(cluster.parent_version.status).to eq("SUPERSEDED")
    expect(cluster.parent_version.members.size).to eq(2)
  end

  it "leaves a consultant's cluster alone and suggests the newcomer instead" do
    quote_finding
    quote_finding
    run!
    approved = ProcessCluster.current.sole.revise!(status: "APPROVED")

    newcomer = quote_finding(hours: [60, 90])
    run = run!
    expect(ProcessCluster.current.sole).to eq(approved)
    expect(approved.reload.members.size).to eq(2)
    expect(run.counts["suggested_additions"]).to include(include("cluster_key" => approved.cluster_key,
                                                                 "finding_id" => newcomer.id))
  end

  it "says the synthesis is stale once a finding changes, and fresh after a re-run" do
    first = quote_finding
    quote_finding
    run!
    expect(Synthesis::Status.for(engagement)["state"]).to eq("needs_review")

    first.update!(what_happens_now: "Now prepared from the new price portal")
    expect(Synthesis::Status.for(engagement)["state"]).to eq("stale")

    run!
    expect(Synthesis::Status.for(engagement)["state"]).not_to eq("stale")
  end

  it "records a failure and leaves the previous synthesis as it was" do
    quote_finding
    quote_finding
    run!
    cluster = ProcessCluster.current.sole
    allow(Synthesis::WorkItems).to receive(:call).and_raise(ActiveRecord::ConnectionTimeoutError, "db gone")

    failed = new_run
    expect { described_class.call(failed, client: client) }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    expect(failed.reload).to have_attributes(status: "FAILED")
    expect(failed.error).to include("db gone")
    expect(ProcessCluster.current.sole).to eq(cluster)
    expect(SynthesisRun.latest_finished(engagement).version).to eq(1)
  end

  it "passes forward unsynthesised, keeping the last synthesis, when P11 can't be used" do
    quote_finding
    quote_finding
    first = run!
    picture = first.operating_picture

    stub_const("ENV", ENV.to_h.merge("AI_SYNTHESIS" => "false"))
    quote_finding(hours: [10, 20])
    second = run!
    expect(second).to have_attributes(status: "PARTIAL", fallback_reason: "model_off")
    expect(second.operating_picture).to eq(picture)
  end

  it "carries an approved operating picture into later runs" do
    quote_finding
    quote_finding
    first = run!
    first.update!(consultant_operating_picture: { "how_the_business_runs" => "Approved wording." },
                  operating_picture_status: "APPROVED")

    second = run!
    expect(second.operating_picture_status).to eq("APPROVED")
    expect(second.display_operating_picture["how_the_business_runs"]).to eq("Approved wording.")
  end

  it "tells task intelligence that synthesis changed" do
    quote_finding
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("synthesis.changed") { |*, payload| events << payload }
    run!
    expect(events.sole).to include(engagement_id: engagement.id, synthesis_version: 1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
