# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportReviews::SubmitService do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user) }
  let(:report) { create(:report, :ready, company: company) }
  let!(:assignment) do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
  end
  let(:review) do
    create(:report_review, report: report, reviewer_user: reviewer, company: company, overall_note: "Looks solid.")
  end

  before do
    ReportSections::KEYS.each do |key|
      review.report_review_section_states.create!(section_key: key, status: "approved")
    end
    review.report_review_findings.create!(
      reviewer_user: reviewer,
      finding_type: "executive_conclusion",
      severity: "info",
      body: "Overall the evidence supports the readiness assessment.",
      publishable: true
    )
    allow(NotificationService).to receive(:notify_review_submitted)
    allow(NotificationService).to receive(:notify_all_reviews_submitted)
  end

  it "submits when all sections are dispositioned and overall note present" do
    described_class.call(report_review: review)
    expect(review.reload).to be_submitted
    expect(report.reload.review_workflow_status).to eq("reviews_complete")
  end

  it "rejects when a section is still pending" do
    review.report_review_section_states.find_by(section_key: "signals").update!(status: "pending")
    expect { described_class.call(report_review: review) }
      .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /signals/)
  end

  it "requires a comment when section needs_info" do
    review.report_review_section_states.find_by(section_key: "signals").update!(status: "needs_info")
    expect { described_class.call(report_review: review) }
      .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /needs_info/)
  end

  it "requires overall conclusion" do
    review.update!(overall_note: "")
    expect { described_class.call(report_review: review) }
      .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /Overall conclusion/)
  end

  it "requires a publishable executive conclusion finding" do
    review.report_review_findings.delete_all
    expect { described_class.call(report_review: review) }
      .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /executive conclusion/)
  end
end
