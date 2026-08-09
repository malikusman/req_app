# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::MetricExtractor do
  let(:company) { create(:company) }

  def ready_doc(filename, *chunks)
    doc = company.documents.create!(filename: filename, storage_key: "k/#{filename}", status: "ready")
    chunks.each_with_index { |c, i| doc.document_chunks.create!(chunk_index: i, content: c) }
    doc
  end

  it "extracts target-vs-actual KPI rows with their source, cited not invented" do
    ready_doc("kpis.txt", "Metric | Target | Current\nAP cycle time (invoice to paid) | 8 days | 11-14 days")

    metrics = described_class.call(company: company)
    ap = metrics.find { |m| m["label"].to_s.match?(/AP cycle time/i) }

    expect(ap).to be_present
    expect(ap["headline"]).to match(/11-14 days/)
    expect(ap["comparison"]).to match(/target 8 days/)
    expect(ap["direction"]).to eq("negative")
    expect(ap["source"]).to eq("Document: kpis.txt")
  end

  it "extracts ratios from interview answers and attributes them to Interview" do
    employee = create(:employee, company: company, department: "finance")
    conversation = create(:conversation, employee: employee, company: company, status: "completed")
    create(:message, conversation: conversation, direction: "inbound", message_type: "text",
                     body: "Roughly 1 in 5 freight invoices fail the three-way match and sit for days.")

    metrics = described_class.call(company: company)
    ratio = metrics.find { |m| m["headline"].to_s.match?(/1 in 5/i) }

    expect(ratio).to be_present
    expect(ratio["source"]).to eq("Interview")
  end

  it "returns nothing when there is no quantified evidence" do
    ready_doc("prose.txt", "The team collaborates well and everyone is aligned on priorities.")

    expect(described_class.call(company: company)).to eq([])
  end

  it "ignores document IDs and dates so they are never shown as metrics" do
    ready_doc("policy.txt", "Document ID: GL-FIN-AP-2026-01 | Effective: 2026-03-01 | Owner: Finance")

    metrics = described_class.call(company: company)
    expect(metrics.map { |m| m["headline"] }).to all(satisfy { |h| !h.match?(/2026|GL-FIN/) })
  end
end
