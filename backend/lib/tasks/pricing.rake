# frozen_string_literal: true

require_relative "../pricing_eval"

namespace :pricing do
  desc "Stage 1 pricing benchmark: the calculator and P24 over spec/fixtures/pricing/scenarios. ONLY=standard,below_floor REAL=1"
  task eval: :environment do
    results = PricingEval.call
    exit(1) if results.any? { |r| r[:failures].any? }
  end

  # How Stage 1 pricing is going (Doc 17 §18): where quotes stand, how long
  # approval and acceptance take, why prices are overridden, and how often P24
  # falls back.
  desc "Stage 1 pricing health over the last DAYS (30)"
  task health: :environment do
    since = ENV.fetch("DAYS", 30).to_i.days.ago
    quotes = Quote.stage1.where(created_at: since..)
    median = lambda do |pairs|
      hours = pairs.filter_map { |a, b| ((b - a) / 3600.0).round(1) if a && b }.sort
      hours.empty? ? "—" : "#{hours[hours.size / 2]} h"
    end

    puts "Stage 1 quotes since #{since.to_date}: #{quotes.count}"
    puts "  By status: #{quotes.group(:status).count}"
    puts "  Below the floor when proposed: #{quotes.where(below_floor: true).count}"
    puts "  Proposed → issued (median): #{median.(quotes.where.not(issued_at: nil).pluck(:created_at, :issued_at))}"
    puts "  Issued → accepted (median): #{median.(quotes.where.not(accepted_at: nil).pluck(:issued_at, :accepted_at))}"
    puts "  Overrides by reason: #{EstimateOverride.where(created_at: since..).group(:kind, :structured_reason).count}"
    puts "  P24 runs: #{AiRun.where(stage: 'P24', created_at: since..).group(:status).count}"
    puts "  P24 fallback reasons: #{AiRun.where(stage: 'P24', status: 'FALLBACK', created_at: since..).group(:fallback_reason).count}"
    puts "  Staff added after an accepted price: #{EngagementParticipant.employees.where(added_after_pricing: true, created_at: since..).count}"
  end
end
