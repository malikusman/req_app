# frozen_string_literal: true

module Reports
  # Checks a report against the rules a Stage 1 diagnostic must keep, before it can
  # be approved for the client. Rule-based on purpose: every check is a pattern or a
  # sum, so it is cheap, repeatable, and says exactly what it objects to.
  #
  # It reads what the client would actually receive — the deliverable rendered with
  # the consultant's edits and the review appendix — plus the findings as they stand
  # now, which may have moved on since the report was generated.
  #
  # "block" issues stop platform approval (overridable only with a recorded
  # reason); "warn" issues are shown to the consultant and the approver.
  class Critic
    Issue = Struct.new(:code, :severity, :section, :message, keyword_init: true) do
      def to_h = { code: code, severity: severity, section: section, message: message }
    end

    # Money and people-cost language. The report measures capacity in hours; it
    # never converts them to salary, cuts or savings (the client's own goal "grow
    # without adding headcount" is theirs to state, so bare "headcount" is allowed).
    PAYROLL = /\b(salar(?:y|ies)|payroll costs?|wage bill|FTEs?\b|full[- ]time equivalents?|headcount (?:reduction|savings?|cuts?)|reduc\w* headcount|cut\w* (?:jobs|staff|headcount|roles)|lay[- ]?offs?|redundanc(?:y|ies)|replac\w* (?:staff|employees|people|workers|the team)|cost savings?|sav\w* AED)\b/i
    MONEY = /(?:\bAED|\bUSD|\bSAR|\$|€|£)\s?\d[\d,.]*(?:\s?(?:k|m|million|thousand))?/i

    # A Stage 1 report says what to address; how it would be built is Stage 2.
    BUILD = /\b(estimated cost|implementation (?:plan|roadmap|steps|timeline)|go[- ]live|proof of concept|sprints?|MVP|\d+[- ](?:weeks?|months?) to (?:build|implement|deliver|deploy)|we(?:'d| would) build|architecture diagram|tech(?:nical)? stack for the build)\b/i

    # Claims the evidence cannot make.
    OVERREACH = /\b(severely|critically|massive(?:ly)?|crippling|dramatic(?:ally)?|guarantee[sd]?|will (?:save|eliminate|double|triple|transform)|eliminat\w* (?:all|every|the need))\b/i

    # A finding written in the first person is a quote, and a quote identifies.
    FIRST_PERSON = /\b(I|I'm|I've|I'd|me|my|mine)\b/

    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
      @company = report.company
      @snapshot = report.report_snapshot || {}
      @issues = []
    end

    def call
      return [] if @snapshot.blank?

      text, text_without_expert = deliverable_text
      check_totals
      check_findings_since_generation
      check_first_person
      check_names(text)
      check_money(text_without_expert)
      check_pattern(text, PAYROLL, "payroll_language", "block",
                    "Converts time into people or money (%<hit>s). Hours are capacity, not a cost to cut.")
      check_pattern(text, BUILD, "build_detail", "block",
                    "Carries build detail (%<hit>s). Stage 1 says what to address; the design is Stage 2.")
      check_pattern(narrative_text, OVERREACH, "overreach", "warn",
                    "Claims more than the evidence shows (%<hit>s).")
      check_coverage
      check_vendors
      @issues.map(&:to_h)
    end

    def self.blocking?(issues) = issues.any? { |i| i[:severity] == "block" }

    private

    def add(code, severity, section, message)
      @issues << Issue.new(code: code, severity: severity, section: section, message: message)
    end

    # The full deliverable as text, and the same without the expert's own page —
    # a consultant's attributed opportunity estimate is their judgement, checked
    # separately below, not a figure the system produced.
    def deliverable_text
      html = RegenerateWithReviewService.render_html(report: @report)
      doc = Nokogiri::HTML(html)
      doc.css("style, script").remove
      full = doc.text.squish
      doc.css(".verdict-page").remove
      [full, doc.text.squish]
    rescue StandardError => e
      Rails.logger.warn("[Reports::Critic] could not render the deliverable: #{e.class}: #{e.message}")
      add("render_failed", "block", nil, "The report could not be rendered to check it.")
      ["", ""]
    end

    def narrative_text
      narrative = @snapshot["narrative"].is_a?(Hash) ? @snapshot["narrative"] : {}
      [
        narrative["governing_thought"], narrative["executive_summary"], narrative["stakes"],
        Array(narrative["supporting_points"]), Array(narrative["implications"]).map { |i| i["statement"] },
        Array(@snapshot.dig("findings", "departments")).flat_map { |d| d["roles"].map { |r| r["potential"] } },
        Array(@snapshot["priorities"]).map { |p| [p["title"], p["what"]] }
      ].flatten.compact.join(" ")
    end

    # A match right after a negation is the report saying what it does NOT do —
    # "they are not converted to salary" — and is not counted.
    NEGATION = /\b(?:not|never|nothing|no|without)\b[^.;:]{0,40}\z/i

    def check_pattern(text, pattern, code, severity, message)
      hits = []
      text.scan(pattern) do
        match = Regexp.last_match
        next if text[[match.begin(0) - 60, 0].max...match.begin(0)].match?(NEGATION)

        hits << match[0].strip
      end
      hits.uniq!
      return if hits.empty?

      add(code, severity, nil, format(message, hit: hits.first(3).map { |h| "“#{h}”" }.join(", ")))
    end

    def check_money(text)
      hits = text.scan(MONEY).uniq
      if hits.any? && !BenchmarkRate.active.exists?
        add("money_without_rates", "block", nil,
            "Prints money (#{hits.first(3).join(', ')}) but no benchmark rates are agreed. Show hours only.")
      end
      return unless @snapshot.dig("expert", "opportunity").present?

      add("expert_money_value", "warn", "expert_verdict",
          "The expert page puts a money value on the opportunity. It is the consultant's own estimate — " \
          "confirm it is attributed and its basis stated.")
    end

    # Every total must equal the rows beneath it: role = its findings, department =
    # its roles, company = its departments, priority = the findings it names.
    def check_totals
      view = @snapshot["findings"]
      return unless view.is_a?(Hash)

      sum = ->(rows) { [rows.sum { |r| r["hours_min"].to_i }, rows.sum { |r| r["hours_max"].to_i }] }
      pair = ->(row) { [row["hours_min"].to_i, row["hours_max"].to_i] }
      broken = []
      departments = Array(view["departments"])
      departments.each do |department|
        department["roles"].each do |role|
          broken << role["title"] if pair.call(role) != sum.call(role["findings"])
        end
        broken << department["name"] if pair.call(department) != sum.call(department["roles"])
      end
      broken << "the company total" if view["totals"] && pair.call(view["totals"]) != sum.call(departments)

      by_id = departments.flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }.index_by { |f| f["id"] }
      Array(@snapshot["priorities"]).each do |priority|
        members = Array(priority["finding_ids"]).filter_map { |id| by_id[id] }
        broken << "priority “#{priority['title']}”" if members.size != Array(priority["finding_ids"]).size ||
                                                      pair.call(priority) != sum.call(members)
      end
      return if broken.empty?

      add("unreconciled_totals", "block", "role_findings",
          "Hours do not add up for #{broken.first(4).to_sentence}. Regenerate the report.")
    end

    # The report is a snapshot; the findings keep moving. Anything shown that a
    # consultant has since hidden, merged or flagged must not ship.
    def check_findings_since_generation
      shown = Array(@snapshot.dig("findings", "departments")).flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }
      return if shown.empty?

      current = @company.findings.where(id: shown.map { |f| f["id"] }).index_by(&:id)
      stale = shown.select do |f|
        finding = current[f["id"]]
        finding.nil? || %w[hidden merged].include?(finding.status) || finding.needs_review?
      end
      if stale.any?
        add("findings_changed", "block", "role_findings",
            "#{stale.size} #{'finding'.pluralize(stale.size)} in this version #{stale.size == 1 ? 'has' : 'have'} " \
            "since been hidden, merged or flagged for review (#{stale.first(3).map { |f| "“#{f['title']}”" }.join(', ')}). " \
            "Regenerate the report.")
      end

      newer = @company.findings.where(status: "approved").where.not(id: shown.map { |f| f["id"] })
                      .where("reviewed_at > ?", @report.generated_at || @report.created_at).count
      return unless newer.positive?

      add("findings_approved_since", "warn", "role_findings",
          "#{newer} #{'finding'.pluralize(newer)} approved since this version was generated. Regenerate to include them.")
    end

    def check_first_person
      quoted = Array(@snapshot.dig("findings", "departments")).flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }
                                                             .select { |f| "#{f['friction']} #{f['what_happens_now']}".match?(FIRST_PERSON) }
      return if quoted.empty?

      add("reads_as_quote", "block", "role_findings",
          "#{quoted.size} #{'finding'.pluralize(quoted.size)} #{quoted.size == 1 ? 'reads' : 'read'} as a quote " \
          "(#{quoted.first(3).map { |f| "“#{f['title']}”" }.join(', ')}). Reword on the Findings page, then regenerate.")
    end

    # The report describes work and roles. A full name anywhere in it — a
    # consultant's added section, an appendix note — identifies someone.
    def check_names(text)
      names = @company.employees.where.not(display_name: [nil, ""]).pluck(:display_name)
                      .map(&:strip).select { |n| n.split.size >= 2 }
      named = names.select { |n| text.match?(/\b#{Regexp.escape(n)}\b/i) }
      return if named.empty?

      add("names_a_person", "block", nil,
          "Names #{named.size} #{named.size == 1 ? 'person' : 'people'} who took part. The report describes work and roles, never individuals.")
    end

    def check_coverage
      view = @snapshot["findings"]
      totals = view.is_a?(Hash) ? view["totals"] || {} : {}
      interviewed = @snapshot.dig("coverage", "completed").to_i
      if totals["findings"].to_i.zero?
        add("no_findings", "warn", "role_findings", "No findings reached this report.") if interviewed.positive?
        return
      end

      share = totals["quantified"].to_f / totals["findings"]
      return if share >= 0.5

      add("few_hours", "warn", "role_findings",
          "Only #{totals['quantified']} of #{totals['findings']} findings carry hours, so the total understates the time.")
    end

    def check_vendors
      named = Array(@snapshot.dig("tools_catalog", "curated_matches")).map { |t| t["name"] }.compact
      return if named.empty?

      add("names_vendors", "warn", "tools_catalog",
          "Names products (#{named.first(3).join(', ')}). Whether vendors belong in Stage 1 is still to be decided.")
    end
  end
end
