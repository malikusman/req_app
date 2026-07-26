# frozen_string_literal: true

require "rails_helper"

RSpec.describe Documents::StartAnalysisRunService do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }

  def create_portal_doc!(status: "uploaded")
    Document.create!(
      company: company,
      source: "company_portal_upload",
      filename: "sop.pdf",
      content_type: "application/pdf",
      byte_size: 100,
      storage_key: "documents/#{company.id}/#{SecureRandom.hex(4)}.pdf",
      status: status,
      document_type: "sop",
      sensitivity: "internal",
      reviewer_visible: true
    )
  end

  it "creates a queued full run and enqueues the job" do
    create_portal_doc!
    expect(DocumentAnalysisRunJob).to receive(:perform_later)

    run = described_class.call(company: company, user: user, run_kind: "full")

    expect(run).to be_persisted
    expect(run.run_kind).to eq("full")
    expect(run.status).to eq("queued")
    expect(run.profile_snapshot["name"]).to eq(company.name)
  end

  it "rejects a second concurrent run" do
    create_portal_doc!
    allow(DocumentAnalysisRunJob).to receive(:perform_later)
    described_class.call(company: company, user: user, run_kind: "full")

    expect {
      described_class.call(company: company, user: user, run_kind: "incremental_docs")
    }.to raise_error(Documents::StartAnalysisRunService::Error, /already in progress/)
  end

  it "requires awaiting docs for incremental_docs" do
    expect {
      described_class.call(company: company, user: user, run_kind: "incremental_docs")
    }.to raise_error(Documents::StartAnalysisRunService::Error, /awaiting analysis/)
  end

  it "allows incremental_docs when uploaded docs exist" do
    create_portal_doc!(status: "uploaded")
    expect(DocumentAnalysisRunJob).to receive(:perform_later)

    run = described_class.call(company: company, user: user, run_kind: "incremental_docs")
    expect(run.run_kind).to eq("incremental_docs")
  end
end
