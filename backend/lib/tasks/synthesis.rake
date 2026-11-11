# frozen_string_literal: true

namespace :synthesis do
  # Runs consolidation and synthesis now for one company's current engagement,
  # in this process — for a consultant who doesn't want to wait for the
  # debounce, and for checking the real model against real evidence.
  desc "Run consolidation and synthesis now. COMPANY=<id or slug> SCRIPTED=1"
  task run: :environment do
    company = Company.find_by(id: ENV["COMPANY"]) || Company.find_by!(slug: ENV.fetch("COMPANY"))
    engagement = company.current_engagement or abort("#{company.name} has no current engagement")
    ENV["SYNTHESIS_SCRIPTED_REPLIES"] = "1" if ENV["SCRIPTED"] == "1"

    run = engagement.with_lock do
      SynthesisRun.create!(company: company, engagement: engagement, trigger: "MANUAL", requested_at: Time.current,
                           version: (SynthesisRun.where(engagement: engagement).maximum(:version) || 0) + 1)
    end
    Synthesis::Run.call(run)
    run.reload
    puts "#{company.name} — synthesis v#{run.version}: #{run.status}#{" (#{run.fallback_reason})" if run.fallback_reason}"
    puts "  Counts: #{run.counts.except('suggested_additions').to_json}"
    puts "  Suggested additions to consultant clusters: #{Array(run.counts['suggested_additions']).size}"
    ProcessCluster.current.where(engagement: engagement).includes(:effort_normalization, :members).each do |c|
      n = c.effort_normalization
      puts format("  %-10s %-11s %-40s members %d  raw %s  de-duplicated %s%s", c.cluster_key, c.status,
                  c.name.to_s.truncate(40), c.members.size, n && "#{n.raw_min}–#{n.raw_max}",
                  n && "#{n.hours_min}–#{n.hours_max}", n&.double_count_warning ? "  (double-count warning)" : "")
    end
    ConsultancyOpportunity.current.where(engagement: engagement).each do |o|
      puts "  #{o.opportunity_key} [#{o.level}/#{o.category}] #{o.title} — management #{o.management_importance || '-'}, " \
           "platform #{o.platform_priority}, next #{o.recommended_next_action}"
    end
    ManagementValidation.current.where(engagement: engagement).includes(:strategic_finding).each do |v|
      puts "  sf_#{v.strategic_finding_id} #{v.relationship}#{' (material)' if v.material}: #{v.management_view.truncate(70)}"
    end
    puts "  Validator drops: #{run.validation_drops.size}"
  end

  # Doc 10 §24: how often the model steps fall back, what the validator removes,
  # and how often consultants overrule the result.
  desc "Synthesis health over the last DAYS (30)"
  task health: :environment do
    since = Integer(ENV.fetch("DAYS", 30)).days.ago
    runs = SynthesisRun.where(created_at: since..)
    puts "Synthesis runs since #{since.to_date}: #{runs.count} #{runs.group(:status).count}"
    durations = runs.where.not(finished_at: nil).pluck(:started_at, :finished_at).filter_map { |s, f| s && (f - s) }
    puts "  Median duration: #{durations.sort[durations.size / 2]&.round || '-'} s" if durations.any?
    AiRun.where(stage: %w[P10 P11], created_at: since..).group(:stage, :status).count.sort.each do |(stage, status), n|
      puts format("  %-4s %-9s %5d", stage, status, n)
    end
    drops = runs.pluck(:validation_drops).flatten
    puts "  Validator drops: #{drops.size}"
    drops.group_by { |d| d["note"].to_s.sub(/:.*/, "").sub(/cites .*/, "cites something that does not exist") }
         .transform_values(&:size).sort_by { |_, n| -n }.first(8).each { |note, n| puts format("    %4d  %s", n, note) }
    decisions = SynthesisDecision.where(created_at: since..)
    puts "  Consultant decisions: #{decisions.count} #{decisions.group(:action).count}"
  end
end
