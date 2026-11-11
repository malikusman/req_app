# frozen_string_literal: true

require "rails_helper"

# Doc 10 §7, §9.4, §20.1: pairs are shortlisted on what the work is, not on
# what it is called, and the model is never asked about a pair twice unless
# one side changed.
RSpec.describe Synthesis::Candidates do
  let(:company) { create(:company, :onboarded) }

  def finding(role:, department: "Sales", title:, what:, hours: [100, 150], **attrs)
    synthesis_finding(company: company, role: role, department: department, title: title,
                      what_happens_now: what, hours: hours, **attrs)
  end

  def items = Synthesis::WorkItems.call(company)

  it "shortlists two accounts of the same quotation work in different words" do
    finding(role: "Sales Coordinator", title: "Preparing quotes",
            what: "I check stock, check the price list, put it into the quotation template and email it to the customer")
    finding(role: "Sales Coordinator", title: "Customer price requests",
            what: "Customer asks for a price; I look up stock availability and our price list and send the quotation")

    pairs = described_class.call(items)
    expect(pairs.size).to eq(1)
    expect(pairs.first.signals.join).to include("same kind of work")
  end

  it "does not shortlist two tasks that only share a name" do
    finding(role: "Finance Analyst", department: "Finance", title: "Weekly report",
            what: "Reconcile bank statements against ledger entries for the treasury committee")
    finding(role: "Warehouse Lead", department: "Operations", title: "Weekly report",
            what: "Count pallets in the yard and log forklift maintenance hours")

    expect(described_class.call(items)).to be_empty
  end

  it "always shortlists one person's two accounts with the same figures" do
    employee = create(:employee, company: company, role_title: "Buyer", department: "Procurement")
    first = finding(role: "Buyer", department: "Procurement", title: "Purchase orders", what: "Raise POs",
                    employee: employee)
    finding(role: "Buyer", department: "Procurement", title: "Supplier follow-up", what: "Chase suppliers",
            employee: employee, evidence: { "possible_duplicate_of" => first.id })

    expect(described_class.call(items).first.signals).to include("The same person gave the same figures for both")
  end

  it "skips a pair already judged, until one side changes" do
    a = finding(role: "Sales Coordinator", title: "Quotes", what: "Prepare customer quotation from stock and price list")
    finding(role: "Sales Coordinator", title: "Quotes", what: "Prepare customer quotation from stock and price list")
    judged = described_class.call(items).map(&:digest).to_set

    expect(described_class.call(items, skip_digests: judged)).to be_empty

    a.update!(what_happens_now: "Prepare customer quotation from stock, price list and the export rules")
    expect(described_class.call(items, skip_digests: judged).size).to eq(1)
  end

  it "maps findings to work items without the hidden or merged ones" do
    kept = finding(role: "Clerk", title: "A", what: "a")
    finding(role: "Clerk", title: "B", what: "b", status: "hidden")
    other = finding(role: "Clerk", title: "C", what: "c")
    other.update!(status: "merged", merged_into: kept)

    expect(items.map(&:id)).to eq([kept.id])
    expect(items.first.evidence).to include({ "type" => "finding", "id" => kept.id })
  end
end
