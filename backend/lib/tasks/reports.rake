# frozen_string_literal: true

namespace :reports do
  desc "Generate report for company SLUG=acme-corp"
  task generate: :environment do
    company = Company.find_by!(slug: ENV.fetch("SLUG", "acme-corp"))
    previous = company.reports.ready.order(version: :desc).first
    report = company.reports.create!(
      version: (company.reports.maximum(:version) || 0) + 1,
      status: "queued",
      visibility: "shared_with_company",
      triggered_by_type: "PlatformUser",
      triggered_by_id: PlatformUser.first!.id,
      previous_report: previous
    )
    Reports::GenerateReportService.call(report: report)
    puts "Report v#{report.version} #{report.status} — #{report.storage_key}"
  end
end
