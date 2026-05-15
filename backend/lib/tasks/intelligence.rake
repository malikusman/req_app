# frozen_string_literal: true

namespace :intelligence do
  desc "Aggregate intelligence for company SLUG=acme-corp"
  task aggregate: :environment do
    company = Company.find_by!(slug: ENV.fetch("SLUG", "acme-corp"))
    result = Intelligence::AggregateCompanyIntelligence.call(company: company)
    puts "Signals: #{result[:signals]}, Patterns: #{result[:patterns]}, Recommendations: #{result[:recommendations]}"
    puts "Readiness: #{company.reload.report_readiness_score}%"
  end
end
