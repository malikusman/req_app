# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::ReviewNotesCollector do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user, name: "Alex Expert") }
  let(:report) { create(:report, :ready, company: company) }
  let!(:submitted) do
    create(:report_review, report: report, reviewer_user: reviewer, company: company,
                           overall_note: "Ready to share.", submitted_at: Time.current, status: "approved")
  end
  let!(:draft) do
    other = create(:reviewer_user, name: "Draft Reviewer", email: "draft@reqapp.local")
    create(:report_review, report: report, reviewer_user: other, company: company, overall_note: "Not ready")
  end

  before do
    create(:report_review_comment, report_review: submitted, reviewer_user: reviewer,
                                   section_key: "signals", body: "Open comment", resolved: false)
    create(:report_review_comment, report_review: submitted, reviewer_user: reviewer,
                                   section_key: "patterns", body: "Resolved comment", resolved: true)
  end

  it "includes only submitted reviews and unresolved comments" do
    notes = described_class.call(report: report)
    bodies = notes.map { |n| n["body"] }
    expect(bodies).to include("Ready to share.", "Open comment")
    expect(bodies).not_to include("Not ready", "Resolved comment")
  end
end
