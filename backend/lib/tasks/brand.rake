# frozen_string_literal: true

# The code rename (Worktruth -> Mjadi) does not reach data that was WRITTEN under
# the old brand. Three places hold it:
#
#   1. solution_catalog_entries — first-party product names ("Worktruth AP Copilot").
#      Live operational data: it is matched into new reports, so leaving it means a
#      freshly generated Mjadi report recommends a Worktruth-branded product.
#   2. agentic_ideas — generated prose naming the first-party product.
#   3. recommendations + company_catalog_matches — DENORMALISED copies of the catalog
#      entry, frozen at match time. Renaming the catalog row alone leaves these, and
#      they are what actually reaches a freshly generated report.
#   4. reports.report_snapshot — generated prose ("Worktruth reviewed 3 documents").
#
# 1-3 are corrected by default. 3 is NOT, and that is deliberate: a snapshot is
# the record of an analysis made at a point in time, and 49 of them here are already
# approved and delivered. Rewriting a shipped document to change a brand string is a
# bigger claim than it looks. Every NEW version regenerates with the new brand
# anyway, and the report chrome (cover, footers, title) is rendered from code, so it
# is already correct even on an old snapshot — only the generated body prose differs.
#
# Pass SNAPSHOTS=1 if you decide historical prose should be rewritten too.
#
#   rake brand:rename                 # dry run, prints what it would change
#   rake brand:rename APPLY=1         # catalog + ideas
#   rake brand:rename APPLY=1 SNAPSHOTS=1
namespace :brand do
  OLD = "Worktruth"
  NEW = "Mjadi"

  desc "Rewrite the old brand in data written before the rename (dry run unless APPLY=1)"
  task rename: :environment do
    apply = ENV["APPLY"] == "1"
    snapshots = ENV["SNAPSHOTS"] == "1"
    label = apply ? "APPLYING" : "DRY RUN"
    puts "#{label} — #{OLD} -> #{NEW}"

    # name, vendor AND slug: renaming only the name leaves "Mjadi AP Copilot" sold
    # by vendor "Worktruth", which is how the last stray reached a fresh snapshot.
    entries = SolutionCatalogEntry.where(
      "name ILIKE :q OR vendor ILIKE :q OR slug ILIKE :q", q: "%#{OLD}%"
    )
    puts "\nsolution_catalog_entries (#{entries.count}):"
    entries.find_each do |entry|
      puts "  #{entry.name.inspect} / vendor=#{entry.vendor.inspect} / slug=#{entry.slug.inspect}"
      next unless apply

      entry.update!(
        name: entry.name.to_s.gsub(OLD, NEW),
        vendor: entry.vendor.to_s.gsub(OLD, NEW).presence,
        slug: entry.slug.to_s.gsub(OLD.downcase, NEW.downcase).gsub(OLD, NEW).presence
      )
    end

    ideas = AgenticIdea.where(
      "title ILIKE :q OR summary ILIKE :q OR system_fit ILIKE :q", q: "%#{OLD}%"
    )
    puts "\nagentic_ideas (#{ideas.count}):"
    ideas.find_each do |idea|
      puts "  ##{idea.id} #{idea.title.to_s.truncate(60)}"
      next unless apply

      idea.update!(
        title: idea.title.to_s.gsub(OLD, NEW),
        summary: idea.summary.to_s.gsub(OLD, NEW),
        system_fit: idea.system_fit.to_s.gsub(OLD, NEW)
      )
    end

    # The catalog entry is copied into these at match time, so renaming the entry
    # alone is not enough -- these are what a newly generated report actually reads.
    recs = Recommendation.where(
      "implementation_outline ILIKE :q OR catalog_matches::text ILIKE :q", q: "%#{OLD}%"
    )
    puts "\nrecommendations (#{recs.count}):"
    recs.find_each do |rec|
      puts "  ##{rec.id} #{rec.title.to_s.truncate(60)}"
      next unless apply

      rec.update!(
        implementation_outline: rec.implementation_outline.to_s.gsub(OLD, NEW),
        catalog_matches: JSON.parse(rec.catalog_matches.to_json.gsub(OLD, NEW))
      )
    end

    matches = CompanyCatalogMatch.where("why_it_fits ILIKE ?", "%#{OLD}%")
    puts "\ncompany_catalog_matches (#{matches.count}):"
    matches.find_each do |match|
      puts "  ##{match.id}"
      match.update!(why_it_fits: match.why_it_fits.to_s.gsub(OLD, NEW)) if apply
    end

    stale = Report.where("report_snapshot::text ILIKE ?", "%#{OLD}%")
    puts "\nreports.report_snapshot (#{stale.count}) — #{snapshots ? 'REWRITING' : 'left alone (pass SNAPSHOTS=1 to rewrite)'}"
    if snapshots
      stale.find_each do |report|
        rewritten = JSON.parse(report.report_snapshot.to_json.gsub(OLD, NEW))
        puts "  v#{report.version} (company #{report.company_id})"
        report.update!(report_snapshot: rewritten) if apply
      end
    end

    puts "\n#{apply ? 'Done.' : 'Nothing changed. Re-run with APPLY=1.'}"
  end
end
