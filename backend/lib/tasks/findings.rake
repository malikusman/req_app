# frozen_string_literal: true

namespace :findings do
  desc "Build findings for every finished interview (SLUG=acme-corp to limit to one company)"
  task backfill: :environment do
    scope = Conversation.where(status: Findings::BuildFromConversation::BUILDABLE)
    scope = scope.where(company: Company.find_by!(slug: ENV["SLUG"])) if ENV["SLUG"].present?
    built = 0
    scope.find_each { |c| built += Findings::BuildFromConversation.call(conversation: c).size }
    with_hours = Finding.where.not(annual_hours_min: nil).count
    puts "Built or refreshed #{built} findings from #{scope.count} interviews (#{with_hours} carry hours)."
  end
end
