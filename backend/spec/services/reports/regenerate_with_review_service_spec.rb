# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::RegenerateWithReviewService do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user, name: "Alex Expert") }
  let(:report) { create(:report, :ready, company: company) }

  before do
    review = create(:report_review, report: report, reviewer_user: reviewer, company: company, overall_note: "Looks solid.")
    create(:report_review_comment, report_review: review, reviewer_user: reviewer, section_key: "signals",
                                   body: "Add more finance evidence.")
    allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, upload: true))
    allow(Reports::PdfGenerator).to receive(:call).and_return("%PDF-1.4 test")
  end

  it "rebuilds the artifact with reviewer notes in the HTML payload" do
    expect(Reports::HtmlBuilder).to receive(:call).with(
      hash_including(
        snapshot: report.report_snapshot,
        review_notes: array_including(
          hash_including("reviewer" => "Alex Expert", "body" => "Looks solid."),
          hash_including("section_key" => "signals", "body" => "Add more finance evidence.")
        )
      )
    ).and_return("<html></html>")

    described_class.call(report: report)

    expect(report.reload.content_type).to eq("application/pdf")
    expect(report.storage_key).to include("reports/#{company.id}/v1/report.pdf")
  end
end
