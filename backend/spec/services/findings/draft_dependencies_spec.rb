# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::DraftDependencies do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:client) { instance_double(Openai::Client, configured?: true) }

  def finding(key, **attrs)
    company.findings.create!({ employee: employee, source_key: key, area: key, title: key.humanize,
                               role_title: "Clerk", friction: "Done by hand", status: "approved" }.merge(attrs))
  end

  # Each needs, first, what the others' work achieves — so the links are grounded.
  let!(:balances) { finding("leave balances", dependency: "Leave requests, payroll inputs and time sheets arrive on time") }
  let!(:requests) do
    finding("leave requests", dependency: "Leave balances are current, and payroll inputs and time sheets agree")
  end
  let!(:payroll) { finding("payroll inputs", dependency: "Leave requests are recorded the same day") }

  before do
    ENV["AI_REPORT_NARRATIVE"] = "true" # switched off suite-wide by spec/support/report_narrative.rb
    allow(Openai::Client).to receive(:new).and_return(client)
  end

  def links(*pairs)
    allow(client).to receive(:finding_dependencies)
      .and_return("links" => pairs.map { |from, to| { "id" => from.id, "depends_on" => to.is_a?(Integer) ? to : to.id } })
  end

  it "keeps the links that stand and writes them on the findings" do
    links([requests, balances])
    described_class.call(company: company)

    expect(requests.reload.depends_on_ids).to eq([balances.id])
    expect(balances.reload.depends_on_ids).to eq([])
  end

  it "drops links to unknown, held-back or hidden findings, and to the finding itself" do
    held = finding("solo work", status: "draft", single_occupant_role: true)
    hidden = finding("set aside", status: "hidden")
    links([requests, 999_999], [requests, held], [requests, hidden], [requests, requests])
    described_class.call(company: company)

    expect(requests.reload.depends_on_ids).to eq([])
  end

  it "follows a link to a merged finding to the one it was merged into" do
    old = finding("old balances")
    old.update!(status: "merged", merged_into: balances)
    links([requests, old])
    described_class.call(company: company)

    expect(requests.reload.depends_on_ids).to eq([balances.id])
  end

  it "cuts a link that would close a loop, including through the consultant's own" do
    links([requests, balances], [balances, requests])
    described_class.call(company: company)
    expect(requests.reload.depends_on_ids).to eq([balances.id])
    expect(balances.reload.depends_on_ids).to eq([])

    payroll.update!(consultant_depends_on_ids: [requests.id])
    links([requests, payroll])
    described_class.call(company: company)
    expect(requests.reload.depends_on_ids).to eq([])
  end

  it "keeps at most two links a finding" do
    extra = finding("time sheets")
    links([requests, balances], [requests, payroll], [requests, extra])
    described_class.call(company: company)

    expect(requests.reload.depends_on_ids).to eq([balances.id, payroll.id])
  end

  it "drops a link the later finding's own words do not ground, shared systems included" do
    orders = finding("customer orders", dependency: "Orders arrive in the ERP as typed text",
                                        direction: "Bring WhatsApp orders into the ERP directly")
    prices = finding("supplier price updates", cause: "Supplier sheets reach the ERP in different layouts")
    links([orders, prices])
    described_class.call(company: company)

    expect(orders.reload.depends_on_ids).to eq([])
  end

  it "keeps the links it had when the model fails" do
    requests.update!(depends_on_ids: [balances.id])
    allow(client).to receive(:finding_dependencies).and_raise(StandardError, "timeout")

    expect(described_class.call(company: company)).to eq({})
    expect(requests.reload.depends_on_ids).to eq([balances.id])
  end
end
