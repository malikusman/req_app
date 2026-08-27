# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsultantAssignments::RemoveService do
  describe ".call" do
    let(:assignment) { create(:consultant_assignment) }
    let(:platform_user) { create(:platform_user) }

    it "marks assignment as removed" do
      result = described_class.call(assignment: assignment, platform_user: platform_user)

      expect(result.status).to eq("removed")
      expect(result.removed_at).to be_present
    end

    it "writes an audit log" do
      expect {
        described_class.call(assignment: assignment, platform_user: platform_user)
      }.to change(PlatformAuditLog, :count).by(1)
    end
  end
end
