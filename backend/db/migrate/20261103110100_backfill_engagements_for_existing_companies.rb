# frozen_string_literal: true

# Every company already using the platform is mid-Stage 1: it gets an engagement
# in STAGE_1_ACTIVE so nobody is locked out or sent back through onboarding.
# Companies still awaiting sign-up approval get one when they are approved.
class BackfillEngagementsForExistingCompanies < ActiveRecord::Migration[7.1]
  def up
    Company.reset_column_information
    Engagement.reset_column_information
    Company.where(approval_status: "approved").where.missing(:engagements).find_each do |company|
      key_user = company.company_users.where(role: "company_admin", status: "active").order(:id).first
      lead = company.consultant_assignments.where(status: "active").order(:id).first&.consultant_user
      Engagement.create!(
        company: company,
        status: "STAGE_1_ACTIVE",
        status_history: [{ "from" => nil, "to" => "STAGE_1_ACTIVE", "at" => Time.current.iso8601,
                           "reason" => "Existing company, carried over" }],
        key_user: key_user,
        lead_consultant: lead,
        languages: [company.locale.presence || "en"],
        onboarding_submitted_at: company.portal_onboarding_completed_at
      )
    end
  end

  def down
    Engagement.where(status: "STAGE_1_ACTIVE").where("status_history->0->>'reason' = ?", "Existing company, carried over")
              .delete_all
  end
end
