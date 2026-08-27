# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsultantAssignments::AssignService do
  describe ".call" do
    let(:company) { create(:company) }
    let(:consultant) { create(:consultant_user) }
    let(:platform_user) { create(:platform_user) }

    it "creates an active assignment" do
      assignment = described_class.call(
        company: company,
        consultant_user: consultant,
        platform_user: platform_user
      )

      expect(assignment).to be_persisted
      expect(assignment.status).to eq("active")
      expect(assignment.company).to eq(company)
      expect(assignment.consultant_user).to eq(consultant)
    end

    it "raises when max active consultants reached" do
      2.times do
        create(:consultant_assignment, company: company, assigned_by_platform_user: platform_user)
      end

      expect {
        described_class.call(company: company, consultant_user: consultant, platform_user: platform_user)
      }.to raise_error(ArgumentError, /Maximum 2 consultants/)
    end

    it "raises when consultant is already assigned" do
      create(:consultant_assignment, company: company, consultant_user: consultant, assigned_by_platform_user: platform_user)

      expect {
        described_class.call(company: company, consultant_user: consultant, platform_user: platform_user)
      }.to raise_error(ArgumentError, "Consultant already assigned")
    end

    it "writes an audit log" do
      expect {
        described_class.call(company: company, consultant_user: consultant, platform_user: platform_user)
      }.to change(PlatformAuditLog, :count).by(1)
    end
  end
end
