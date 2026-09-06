# frozen_string_literal: true

require "rails_helper"

RSpec.describe Documents::PurgeService do
  let(:company) { create(:company) }
  let(:document) do
    Document.create!(
      company: company,
      source: "company_portal_upload",
      filename: "policy.pdf",
      content_type: "application/pdf",
      byte_size: 100,
      storage_key: "documents/#{company.id}/test/policy.pdf",
      status: "ready",
      document_type: "policy",
      sensitivity: "internal",
      consultant_visible: true
    )
  end

  it "purges storage metadata and marks the document purged" do
    original_key = document.storage_key
    client = instance_double(Storage::MinioClient, delete: true)
    allow(Storage::MinioClient).to receive(:new).and_return(client)
    allow(AggregateIntelligenceJob).to receive(:perform_later)

    described_class.call(document: document)

    expect(client).to have_received(:delete).with(original_key)
    expect(document.reload.storage_key).to start_with("purged/")
    expect(document.metadata["purged"]).to eq(true)
    expect(document.purged_at).to be_present
    expect(AggregateIntelligenceJob).to have_received(:perform_later).with(company.id)
  end

  it "orphans knowledge entries that only cited the purged document" do
    entry = company.company_knowledge_entries.create!(
      entry_type: "policy",
      title: "Only this doc",
      content: "Rule from policy.pdf",
      status: "active",
      source_document_ids: [document.id]
    )
    allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, delete: true))
    allow(AggregateIntelligenceJob).to receive(:perform_later)

    described_class.call(document: document)

    expect(entry.reload.status).to eq("orphaned")
  end
end
