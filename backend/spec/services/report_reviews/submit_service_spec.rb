# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportReviews::SubmitService do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:report) { create(:report, :ready, company: company) }
  let!(:assignment) do
    create(:consultant_assignment, company: company, consultant_user: consultant)
  end
  let(:review) do
    create(:report_review, report: report, consultant_user: consultant, company: company, overall_note: "Looks solid.")
  end

  before do
    ReportSections::KEYS.each do |key|
      review.report_review_section_states.create!(section_key: key, status: "approved")
    end
    review.report_review_findings.create!(
      consultant_user: consultant,
      finding_type: "executive_conclusion",
      severity: "info",
      body: "Overall the evidence supports the readiness assessment.",
      publishable: true
    )
    allow(NotificationService).to receive(:notify_review_submitted)
    allow(NotificationService).to receive(:notify_all_reviews_submitted)
    allow(Reports::Critic).to receive(:call).and_return([])
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

  describe "a finding waiting for review" do
    let(:employee) { create(:employee, company: company, role_title: "Fleet Planner") }
    let!(:flagged) do
      company.findings.create!(employee: employee, source_key: "k1", area: "route planning", department: "ops",
                               role_title: "Fleet Planner", friction: "Routes are planned by hand",
                               single_occupant_role: true)
    end

    it "refuses until the consultant has decided it" do
      expect { described_class.call(report_review: review) }
        .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /1 finding needs your review/)
    end

    it "submits once it is approved" do
      flagged.update!(status: "approved")
      described_class.call(report_review: review)
      expect(review.reload).to be_submitted
    end
  end

  it "refuses while the report fails a required check" do
    allow(Reports::Critic).to receive(:call).and_return(
      [{ code: "build_detail", severity: "block", section: nil, message: "Carries build detail (“go-live”)." },
       { code: "few_hours", severity: "warn", section: "role_findings", message: "Only 1 of 4 findings carry hours." }]
    )
    expect { described_class.call(report_review: review) }
      .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /fails 1 required check: Carries build detail/)
  end

  it "requires a publishable executive conclusion finding" do
    review.report_review_findings.delete_all
    expect { described_class.call(report_review: review) }
      .to raise_error(ReportReviews::SubmitService::IncompleteReviewError, /executive conclusion/)
  end
end
