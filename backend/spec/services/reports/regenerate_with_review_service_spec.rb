# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::RegenerateWithReviewService do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user, name: "Alex Expert") }
  let(:report) { create(:report, :ready, company: company) }

  before do
    review = create(:report_review, report: report, consultant_user: consultant, company: company,
                                    overall_note: "Looks solid.", submitted_at: Time.current, status: "approved")
    create(:report_review_comment, report_review: review, consultant_user: consultant, section_key: "signals",
                                   body: "Add more finance evidence.")
    review.report_review_findings.create!(
      consultant_user: consultant,
      finding_type: "executive_conclusion",
      severity: "info",
      disposition: "endorse",
      body: "Ready for platform approval.",
      evidence_refs: %w[signal:finance-1],
      publishable: true
    )
    allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, upload: true))
    allow(Reports::PdfGenerator).to receive(:call).and_return("%PDF-1.4 test")
  end

  it "rebuilds the artifact with consultant notes in the HTML payload" do
    expect(Reports::HtmlBuilder).to receive(:call).with(
      hash_including(
        snapshot: report.report_snapshot,
        review_notes: array_including(
          hash_including("consultant" => "Alex Expert", "body" => "Looks solid."),
          hash_including("section_key" => "signals", "body" => "Add more finance evidence.")
        ),
        review_overlay: hash_including(
          "structured_findings" => array_including(
            hash_including(
              "body" => "Ready for platform approval.",
              "disposition" => "endorse",
              "evidence_refs" => %w[signal:finance-1]
            )
          )
        )
      )
    ).and_return("<html></html>")

    described_class.call(report: report)

    expect(report.reload.content_type).to eq("application/pdf")
    expect(report.storage_key).to include("reports/#{company.id}/v#{report.version}/report.pdf")
  end
end
