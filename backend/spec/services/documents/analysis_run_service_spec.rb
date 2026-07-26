# frozen_string_literal: true

require "rails_helper"

RSpec.describe Documents::AnalysisRunService do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }
  let!(:document) do
    Document.create!(
      company: company,
      source: "company_portal_upload",
      filename: "ap-sop.txt",
      content_type: "text/plain",
      byte_size: 40,
      storage_key: "documents/#{company.id}/ap-sop.txt",
      status: "uploaded",
      document_type: "sop",
      sensitivity: "internal",
      reviewer_visible: true
    )
  end
  let(:run) do
    company.document_analysis_runs.create!(
      triggered_by_company_user: user,
      run_kind: "full",
      status: "queued",
      phase: "queued",
      document_ids: [document.id],
      profile_snapshot: { "name" => company.name }
    )
  end

  before do
    allow(Documents::IngestDocumentService).to receive(:call).and_return(
      ok: true, text: "Invoice approval requires two signatures above 5000 AED.", chunk_count: 1
    )
    allow(Documents::ClarificationRagService).to receive(:call)
    allow(AggregateIntelligenceJob).to receive(:perform_later)
    allow(Langgraph::Client).to receive(:new).and_return(
      instance_double(
        Langgraph::Client,
        run_docs_analysis!: {
          "knowledge_entries" => [
            {
              "entry_type" => "process",
              "title" => "Dual approval",
              "content" => "Two signatures required above 5000 AED",
              "confidence" => 0.9,
              "source_document_ids" => [document.id]
            }
          ],
          "questions" => [
            { "body" => "What ERP system posts approved invoices?", "rationale" => "gap" }
          ],
          "events" => [
            { "agent_name" => "specialist", "event_type" => "step", "message" => "Extracted process" }
          ],
          "summary" => "OK"
        }
      )
    )
  end

  it "persists KB entries, questions, events, and marks docs ready" do
    described_class.call(run_id: run.id)

    run.reload
    expect(run.status).to eq("completed")
    expect(company.company_knowledge_entries.active.count).to eq(1)
    expect(company.company_clarification_questions.count).to eq(1)
    expect(run.document_analysis_events.count).to be >= 2
    expect(document.reload.status).to eq("ready")
    expect(AggregateIntelligenceJob).to have_received(:perform_later).with(company.id)
  end
end
