# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAuditService do
  describe ".log!" do
    it "persists platform audit logs" do
      user = create(:platform_user)
      company = create(:company)

      described_class.log!(
        platform_user: user,
        action: "company_created",
        target: company,
        metadata: { name: company.name }
      )

      log = PlatformAuditLog.last
      expect(log.action).to eq("company_created")
      expect(log.target_type).to eq("Company")
      expect(log.target_id).to eq(company.id)
    end
  end
end
