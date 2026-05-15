# frozen_string_literal: true

namespace :notifications do
  desc "Send a test notification to company admins (SLUG=acme-corp)"
  task test: :environment do
    company = Company.find_by!(slug: ENV.fetch("SLUG", "acme-corp"))
    NotificationService.notify(
      type: :test,
      company: company,
      recipients: company.company_users.where(role: "company_admin", status: "active"),
      title: "Test notification",
      body: "This is a test in-app notification from Phase 7.",
      action_url: "#{NotificationService.app_host}/company/dashboard"
    )
    puts "Sent test notification to #{company.name} admins"
  end
end
