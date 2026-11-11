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

    # Hours "a day", "per invoice": how long one piece of work takes, which the
    # consultant may quote from the conversation. Only yearly hours must be ones the
    # findings carry.
    PER_PERIOD_HOURS = /\d[\d,.]*(?:\s*(?:–|—|-|to)\s*\d[\d,.]*)?\s*(?:hours?|hrs?)\s+(?:a|an|per|each|every)\s+(?!year)\w+/i

    # A conclusion about the whole company, which partial coverage cannot support
    # (Doc 15 §13.3).
    COMPANY_WIDE = /\b(across the (?:company|business|organi[sz]ation)|company[- ]wide|organi[sz]ation[- ]wide|every (?:department|team)|all (?:departments|teams)|the whole (?:company|business))\b/i

    # Mjadi's own commercial terms and the rates behind a value. The value of
    # capacity is shown; the hourly rate it was worked out with is not. Worded as
    # ours on purpose: a client's own "margins" or "sales commission" are their
    # business and may well be a finding.
    COMMERCIAL = /\b((?:our|mjadi(?:'s)?) (?:margins?|mark-?ups?|fees?|commissions?|internal costs?|delivery costs?)|referral fees?|partner(?:ship)? tiers?|(?:internal )?cost basis)\b/i
    HOURLY_RATE = /(?:\bAED|\bUSD|\bSAR|\$|€|£)\s?\d[\d,.]*\s*(?:an|per|\/)\s*h(?:ou)?r\b/i

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
      check_consultant_figures
      check_role_capacity
      check_specificity
      check_duplicates
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
      check_coverage_reach
      check_pattern(text, HOURLY_RATE, "commercial_data", "block",
                    "Shows an hourly rate (%<hit>s). The value of capacity is shown; the rate behind it stays internal.")
      check_pattern(text, COMMERCIAL, "commercial_data", "block",
                    "Carries commercial terms (%<hit>s). Internal rates, margins and fees are not for the client.")
      check_coverage
      check_vendors
      check_stage2_sections
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
    # its roles, company = its departments, priority = the findings it names. A
    # finding counted with another (shared work, Doc 10 §10.3) adds nothing.
    def check_totals
      view = @snapshot["findings"]
      return unless view.is_a?(Hash)

      sum = ->(rows) { [rows.sum { |r| r["hours_min"].to_i }, rows.sum { |r| r["hours_max"].to_i }] }
      # In a role, a finding counted with another never adds; in a priority, only
      # when the one it is counted with is in the same priority.
      in_role = ->(rows) { sum.call(rows.reject { |r| r["counted_in"] }) }
      in_theme = lambda do |rows|
        ids = rows.map { |r| r["id"] }
        sum.call(rows.reject { |r| r["counted_in"] && ids.include?(r["counted_in"]["id"]) })
      end
      pair = ->(row) { [row["hours_min"].to_i, row["hours_max"].to_i] }
      broken = []
      departments = Array(view["departments"])
      departments.each do |department|
        department["roles"].each do |role|
          broken << role["title"] if pair.call(role) != in_role.call(role["findings"])
        end
        broken << department["name"] if pair.call(department) != sum.call(department["roles"])
      end
      broken << "the company total" if view["totals"] && pair.call(view["totals"]) != sum.call(departments)

      by_id = departments.flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }.index_by { |f| f["id"] }
      Array(@snapshot["priorities"]).each do |priority|
        members = Array(priority["finding_ids"]).filter_map { |id| by_id[id] }
        broken << "priority “#{priority['title']}”" if members.size != Array(priority["finding_ids"]).size ||
                                                      pair.call(priority) != in_theme.call(members)
      end
      return if broken.empty?

      add("unreconciled_totals", "block", "role_findings",
          "Hours do not add up for #{broken.first(4).to_sentence}. Regenerate the report.")
    end

    # The writer may quote only the computed figures (NarrativeWriter grounds it
    # sentence by sentence); a consultant types freely. Their figures are read the
    # same way, with Llm::GroundedNumbers, against everything the report carries
    # (Doc 15 §12, Reconciliation):
    #   - a yearly hours figure must be one the findings, roles, departments, totals
    #     or priorities add up to, else the cover says 490 where the findings say
    #     470 — that blocks;
    #   - any other figure — "25 orders", "2 hours a day", "30%" — may be what
    #     someone said in an interview, which the report does not carry, so it is
    #     shown to the consultant to check, not blocked.
    def check_consultant_figures
      allowed = allowed_figures
      consultant_texts.each do |where, section_key, body|
        stray = Llm::GroundedNumbers.figures(body) - allowed
        next if stray.empty?

        per_period = Llm::GroundedNumbers.figures(body.scan(PER_PERIOD_HOURS).join(" "))
        yearly, other = stray.partition { |f| f.match?(/\A[\d.]+(?:hour|hr)\z/) && !per_period.include?(f) }
        other.select! { |f| f.match?(/\A[\d.]+[a-z]+\z|%\z|\A(?:aed|\$)/) }
        if yearly.any?
          add("unreconciled_figures", "block", section_key,
              "“#{where}” states #{figure_words(yearly)}, which no finding, role or total adds up to. " \
              "Quote the findings' figures, or correct the finding on the Findings page and regenerate.")
        end
        next if other.empty?

        add("ungrounded_figures", "warn", section_key,
            "“#{where}” quotes #{figure_words(other)}, which nothing in the report carries. Check it against what " \
            "was said, and that it reads as the people's account, not a measurement.")
      end
    end

    # The consultant's own text the client will read: published edits and added
    # sections, less edits to sections they hid.
    def consultant_texts
      @consultant_texts ||= begin
        overrides = @report.report_section_overrides.published.to_a
        hidden = overrides.select { |o| o.action == "hide" }.map(&:section_key)
        overrides.select { |o| %w[edit add].include?(o.action) }
                 .reject { |o| o.action == "edit" && hidden.include?(o.section_key) }
                 .map { |o| [o.title.presence || ReportsHelper.section_label(o.section_key), o.section_key, o.body.to_s] }
      end
    end

    # Every figure the report itself carries, written the ways it prints them.
    def allowed_figures
      view = @snapshot["findings"].is_a?(Hash) ? @snapshot["findings"] : {}
      departments = Array(view["departments"])
      roles = departments.flat_map { |d| d["roles"] }
      rows = [view["totals"]].compact + departments + roles + shown_rows + Array(@snapshot["priorities"])
      written = ->(n) { [n.to_s, ActiveSupport::NumberHelper.number_to_delimited(n)].uniq }
      sources = rows.flat_map do |row|
        figures = []
        if row["hours_min"]
          written.call(row["hours_min"]).product(written.call(row["hours_max"])).each do |low, high|
            figures << "#{low} hours" << "#{high} hours" << "#{low}–#{high} hours"
          end
        end
        if row["value_min"]
          figures << "#{row['currency']} #{row['value_min']}" << "#{row['currency']} #{row['value_max']}"
          figures << "#{row['currency']} #{ActiveSupport::NumberHelper.number_to_delimited(row['value_min'])}–" \
                     "#{ActiveSupport::NumberHelper.number_to_delimited(row['value_max'])}"
        end
        figures + [row["frequency"], row["duration"]].compact
      end
      coverage = @snapshot["coverage"].is_a?(Hash) ? @snapshot["coverage"] : {}
      counts = [coverage["invited"], coverage["completed"], coverage["roles_interviewed"]] +
               Array(coverage["departments"]).flat_map { |d| [d["invited"], d["completed"]] }
      sources += counts.compact.flat_map { |n| ["#{n} people", "#{n} employees", "#{n} staff"] }
      sources += Array(@snapshot["key_metrics"]).flat_map { |m| [m["headline"], m["comparison"]] }
      Llm::GroundedNumbers.allowed_numbers(sources.compact)
    end

    # "490hour" → "490 hours", as GroundedNumbers keys a quantity.
    def figure_words(figures)
      figures.first(3).map { |f| f.sub(/\A([\d.]+)([a-z]+)\z/) { "#{Regexp.last_match(1)} #{Regexp.last_match(2).pluralize}" } }
             .to_sentence
    end

    def shown_rows
      @shown_rows ||= Array(@snapshot.dig("findings", "departments")).flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }
    end

    # A finding names a piece of work: the role that does it, and how often or how
    # long it takes. Without either it is a theme dressed as a finding (Doc 15 §12,
    # Specificity). A wait is exempt — how long it lasts is the finding.
    def check_specificity
      return if shown_rows.empty?

      roles = @company.findings.where(id: shown_rows.map { |f| f["id"] }).pluck(:id, :role_title).to_h
      vague = shown_rows.select do |f|
        roles[f["id"]].blank? ||
          (f["frequency"].blank? && f["duration"].blank? && f["effort_type"] != "waiting")
      end
      return if vague.empty?

      add("not_specific", "block", "role_findings",
          "#{vague.size} #{'finding'.pluralize(vague.size)} #{vague.size == 1 ? 'reads' : 'read'} as a theme, not a " \
          "piece of work (#{vague.first(3).map { |f| "“#{f['title']}”" }.join(', ')}): each needs a role, and how often " \
          "or how long. Correct figures or hide it on the Findings page, then regenerate.")
    end

    # Two findings for one piece of work (Doc 15 §12, Duplication). Heuristic, so it
    # warns: the consultant decides. Two people each doing their own share of a task
    # is not a duplicate — merging would drop real hours — so only the same person's
    # findings are compared for the same work, and any findings for the same cause.
    def check_duplicates
      return if shown_rows.size < 2

      records = @company.findings.where(id: shown_rows.map { |f| f["id"] }).index_by(&:id)
      same_work = records.values.select(&:employee_id).group_by(&:employee_id).values.flat_map do |mine|
        mine.combination(2).select do |a, b|
          overlap(words(a.display_title), words(b.display_title)) >= 0.5 || same_duration?(a, b)
        end
      end
      if same_work.any?
        add("possible_duplicate", "warn", "role_findings",
            "One person's findings may be the same work named twice: " \
            "#{same_work.first(3).map { |a, b| "“#{a.display_title}” and “#{b.display_title}”" }.join("; ")}. " \
            "If they describe the same effort, merge them on the Findings page; if not, approve both.")
      end

      caused = shown_rows.select { |f| f["cause"].present? }
      same_cause = caused.combination(2).select { |a, b| overlap(words(a["cause"]), words(b["cause"])) >= 0.7 }
      return if same_cause.empty?

      add("possible_duplicate", "warn", "role_findings",
          "Several findings give the same cause: " \
          "#{same_cause.first(3).map { |a, b| "“#{a['title']}” and “#{b['title']}”" }.join("; ")}. " \
          "If they describe the same effort, merge them; if each person does their own, keep both.")
    end

    def words(text) = Findings::Words.of(text)
    def overlap(one, other) = Findings::Words.overlap(one, other)

    def same_duration?(one, other)
      a = one.effective_effort.values_at(:duration_min, :duration_max, :duration_unit)
      b = other.effective_effort.values_at(:duration_min, :duration_max, :duration_unit)
      a.first.present? && a.map(&:to_s) == b.map(&:to_s)
    end

    # A report may be released from partial coverage, but then no company-wide
    # conclusion may be drawn (Doc 15 §13.3), and a department nobody spoke for is
    # not described. Read on the written prose and the consultant's own text — the
    # report's own labels ("Roles across the company") are not conclusions.
    def check_coverage_reach
      coverage = @snapshot["coverage"]
      return unless coverage.is_a?(Hash)

      uncovered = (Array(coverage["departments"]).select { |d| d["completed"].to_i.zero? }.map { |d| d["department"] } +
                   Array(coverage["not_interviewed"])).map(&:to_s).reject { |d| d.blank? || d == "Not recorded" }
                                                     .uniq(&:downcase)
      return if uncovered.empty?

      prose = ([narrative_text] + consultant_texts.map(&:last)).join(" ")
      names = uncovered.map { |d| ReportsHelper.report_department_label(d) }.to_sentence
      check_pattern(prose, COMPANY_WIDE, "overreach_coverage", "block",
                    "Draws a company-wide conclusion (%<hit>s), but nobody in #{names.gsub('%', '%%')} was interviewed. " \
                    "Say what the evidence covers.")

      with_findings = Array(@snapshot.dig("findings", "departments")).map { |d| d["name"].to_s.downcase }
      unspoken = uncovered.reject { |d| with_findings.include?(d.downcase) }
      return if unspoken.empty?

      check_pattern(prose, /\b(#{unspoken.map { |d| Regexp.escape(d) }.join('|')})\b/i, "uncovered_department", "warn",
                    "Describes %<hit>s, where nobody was interviewed and no finding sits. Check the claim stands.")
    end

    # Each finding is capped at what one person can work; a role's findings together
    # can still pass what its people work in a year. When they do, the same work
    # was most likely counted twice, or elapsed time was taken for effort.
    def check_role_capacity
      year = Findings::AnnualHours::WORKING_DAYS * Findings::AnnualHours::HOURS_PER_DAY
      over = Array(@snapshot.dig("findings", "departments")).flat_map { |d| d["roles"] }.select do |role|
        people = [role["people"].to_i, 1].max
        role["hours_max"].to_i > people * year
      end
      return if over.empty?

      add("role_over_capacity", "warn", "role_findings",
          "#{over.map { |r| "“#{r['title']}”" }.first(3).to_sentence} #{over.size == 1 ? 'claims' : 'claim'} more hours " \
          "than #{over.size == 1 ? 'its' : 'their'} people work in a year (#{year} each). Look for the same work counted " \
          "twice, or a wait counted as effort, on the Findings page.")
    end

    # The report is a snapshot; the findings keep moving. Anything shown that a
    # consultant has since hidden, merged or flagged must not ship.
    def check_findings_since_generation
      shown = shown_rows
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
      quoted = shown_rows.select { |f| "#{f['friction']} #{f['what_happens_now']}".match?(FIRST_PERSON) }
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

    # A consultant section built from a Stage 2 template — an implementation plan —
    # describes how the fix is delivered. The template is no longer offered, but a
    # report reviewed before that may still carry one forward.
    def check_stage2_sections
      titles = @report.report_section_overrides.published
                      .where(action: "add", section_key: ReportSectionTemplates::STAGE2_KEYS)
                      .pluck(:title)
      return if titles.empty?

      add("stage2_section", "block", nil,
          "Includes a Stage 2 section (#{titles.first(3).map { |t| "“#{t}”" }.join(', ')}). " \
          "Owners, effort and milestones belong to the design; remove the section.")
    end

    # Products and ideas name what would do the work, which is Stage 2's. They reach
    # a report only when report_stage2_previews is "shown", and then they block.
    def check_vendors
      named = Array(@snapshot.dig("tools_catalog", "curated_matches")).map { |t| t["name"] }.compact
      if named.any?
        add("names_vendors", "block", "tools_catalog",
            "Names products (#{named.first(3).join(', ')}). Stage 1 says what to address, not which product; " \
            "set report_stage2_previews to hidden and regenerate.")
      end

      ideas = Array(@snapshot["agentic_ideas"]).map { |i| i["title"] }.compact
      return if ideas.empty?

      add("shows_ideas", "block", "opportunities",
          "Publishes ideas (#{ideas.first(3).map { |t| "“#{t}”" }.join(', ')}). Stage 1 does not publish ideas; " \
          "set report_stage2_previews to hidden and regenerate.")
    end
  end
end
