# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReviewerAssignments::AssignService do
  describe ".call" do
    let(:company) { create(:company) }
    let(:reviewer) { create(:reviewer_user) }
    let(:platform_user) { create(:platform_user) }

    it "creates an active assignment" do
      assignment = described_class.call(
        company: company,
        reviewer_user: reviewer,
        platform_user: platform_user
      )

      expect(assignment).to be_persisted
      expect(assignment.status).to eq("active")
      expect(assignment.company).to eq(company)
      expect(assignment.reviewer_user).to eq(reviewer)
    end

    it "raises when max active reviewers reached" do
      2.times do
        create(:reviewer_assignment, company: company, assigned_by_platform_user: platform_user)
      end

      expect {
        described_class.call(company: company, reviewer_user: reviewer, platform_user: platform_user)
      }.to raise_error(ArgumentError, /Maximum 2 reviewers/)
    end

    it "raises when reviewer is already assigned" do
      create(:reviewer_assignment, company: company, reviewer_user: reviewer, assigned_by_platform_user: platform_user)

      expect {
        described_class.call(company: company, reviewer_user: reviewer, platform_user: platform_user)
      }.to raise_error(ArgumentError, "Reviewer already assigned")
    end

    it "writes an audit log" do
      expect {
        described_class.call(company: company, reviewer_user: reviewer, platform_user: platform_user)
      }.to change(PlatformAuditLog, :count).by(1)
    end
  end
end
