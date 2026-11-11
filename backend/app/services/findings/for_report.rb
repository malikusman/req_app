# frozen_string_literal: true

module Findings
  # The findings as the report reads them: department, then role, then task, with
  # the hours each costs and the totals they add up to.
  #
  # Every number here is computed in Ruby from the findings themselves, so a total
  # always reconciles with the rows beneath it — the report writer is handed these
  # figures and may quote only them.
  #
  # What reaches a client:
  #   - approved findings, and drafts a consultant has not yet looked at;
  #   - never hidden ones, and never merged ones — their hours are already counted
  #     in the finding they were merged into;
  #   - never an unreviewed finding about a role only one person holds, because it
  #     describes that person. Those are counted in `withheld` for the consultant,
  #     not shown.
  #
  # Shared work a consultant confirmed in synthesis (Doc 10 §10.3) is counted
  # once: where two findings describe the same execution, the one synthesis
  # set aside keeps its row and its own figures but is marked as counted with
  # the other, and no total adds it again. Each finding in shared work spanning
  # departments points to where else it appears (Doc 15 §4.5).
  class ForReport
    CONFIDENCE = 0.6

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      shown = shown_findings
      merged_into = @company.findings.where(status: "merged").where(merged_into_id: shown.map(&:id))
                            .pluck(:merged_into_id, :employee_id)
                            .group_by(&:first).transform_values { |rows| rows.map(&:last) }

      departments = shown.group_by { |f| f.department.presence || "Other" }.map do |name, rows|
        roles = rows.group_by { |f| f.role_title.presence || "Role not recorded" }.map do |title, items|
          role_json(title, items, merged_into)
        end
        roles.sort_by! { |r| [-r["hours_max"].to_i, r["title"]] }
        { "name" => name, "roles" => roles }.merge(range(roles.flat_map { |r| r["findings"] }))
      end
      departments = pool_small_roles(departments) if @company.merged_settings["report_small_roles"] != "show"
      departments.sort_by! { |d| [-d["hours_max"].to_i, d["name"]] }
      attach_links(departments)
      attach_shared_work(departments)

      all = departments.flat_map { |d| d["roles"] }.flat_map { |r| r["findings"] }
      {
        "departments" => departments,
        "totals" => {
          "findings" => all.size,
          "quantified" => all.count { |f| f["hours_min"] },
          # Counted from the findings, not the groups: pooling one-person roles
          # must not make "6 roles in 5 departments" read as "3 in 3".
          "roles" => shown.map { |f| [f.department.to_s.downcase, f.role_title.to_s.downcase] }.uniq.size,
          "departments" => shown.map { |f| f.department.to_s.downcase }.uniq.size,
          "people" => shown.map(&:employee_id).compact.uniq.size
        }.merge(range(all)),
        "delays" => all.select { |f| f["effort_type"] == "waiting" }.map do |f|
          f.slice("title", "role", "department", "duration")
        end,
        "withheld" => @withheld_count,
        "basis" => AnnualHours::BASIS,
        # The benchmark rates the values were worked out with, printed in the
        # report. Empty means no rates are agreed, and the report shows hours only.
        "rates" => @rates_used.to_a.map { |r| { "version" => r.version, "role_family" => r.role_family, "currency" => r.currency } }
      }
    end

    # What each role's people said they would do with more time, for the report
    # writer to turn into one line about the role. Deliberately NOT part of the
    # snapshot: it is closer to what someone said than a finding is, and the
    # snapshot is served to the client over the API.
    def role_potential_notes
      shown = shown_findings
      pooling = @company.merged_settings["report_small_roles"] != "show"
      shown.group_by { |f| [f.department.presence || "Other", f.role_title.presence || "Role not recorded"] }
           .filter_map do |(department, role), items|
        # A line about a role one person holds is a line about that person.
        next if pooling && items.map(&:employee_id).compact.uniq.size < POOL_MIN
        notes = items.map(&:conversation).compact.uniq.filter_map do |conversation|
          entry = conversation.blackboard.dig("dossier", "slots", "role_potential")
          entry["value"].to_s.strip.presence if entry.is_a?(Hash) && entry["confidence"].to_f >= CONFIDENCE
        end
        { "department" => department, "role" => role, "notes" => notes } if notes.any?
      end
    end

    private

    def shown_findings
      @shown_findings ||= begin
        live = @company.findings.where(status: %w[draft approved]).includes(:conversation).order(:id).to_a
        withheld, shown = live.partition(&:needs_review?)
        @withheld_count = withheld.size
        shown
      end
    end

    def role_json(title, items, merged_into)
      findings = items.map do |f|
        people = ([f.employee_id] + Array(merged_into[f.id])).compact.uniq.size
        {
          "id" => f.id,
          "title" => f.display_title.to_s.upcase_first,
          "department" => f.department,
          "role" => f.role_title,
          "friction" => f.display_friction,
          "what_happens_now" => f.display_what_happens_now,
          "frequency" => f.display_frequency,
          "duration" => f.display_duration,
          "effort_type" => f.effective_effort_type,
          "hours_min" => f.annual_hours_min,
          "hours_max" => f.annual_hours_max,
          **value_for(f),
          "people" => people,
          "confidence" => f.confidence,
          "basis" => f.basis,
          **counted_once(f),
          # Only a cause and direction drafted from the wording shown here, or the
          # consultant's own; a draft for wording since changed is left out.
          **cause_and_direction(f)
        }
      end
      findings.sort_by! { |f| [-f["hours_max"].to_i, f["title"]] }
      people = items.flat_map { |f| [f.employee_id] + Array(merged_into[f.id]) }.compact.uniq.size
      { "title" => title, "people" => people, "findings" => findings, "potential" => nil }.merge(range(findings))
    end

    # The findings each one must come after, as the report shows them: a link to a
    # merged finding follows it to the one it was merged into, and a link to
    # anything not shown — hidden, or held back for review — is dropped, since
    # naming it would reveal it. Rows are read after pooling, so a target in the
    # company-wide pool carries no department, exactly as it is shown.
    def attach_links(departments)
      rows = departments.flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }
      by_id = rows.index_by { |r| r["id"] }
      records = shown_findings.index_by(&:id)
      merged = @company.findings.merge_targets
      rows.each do |row|
        ids = Array(records[row["id"]]&.effective_depends_on_ids).map { |id| merged.fetch(id, id) }.uniq - [row["id"]]
        row["depends_on"] = ids.filter_map { |id| by_id[id]&.slice("id", "title", "department") }
      end
    end

    def cause_and_direction(finding)
      fresh = !finding.draft_stale?
      cause = finding.consultant_cause.presence || (fresh ? finding.cause : nil)
      direction = finding.consultant_direction.presence || (fresh ? finding.direction : nil)
      type = finding.consultant_intervention_type.presence || (fresh ? finding.intervention_type : nil)
      dependency = finding.consultant_dependency.presence || (fresh ? finding.dependency : nil)
      {
        "cause" => cause,
        "cause_stated" => cause.present? && finding.display_cause_stated,
        "intervention_type" => type,
        "intervention" => Finding::INTERVENTION_TYPES[type],
        "direction" => direction,
        "dependency" => dependency
      }
    end

    # A role held by one person describes that person, approved or not. So a
    # report never shows one: those roles pool into "Other roles" in their
    # department when that brings at least two people together, and otherwise
    # into one pool across the company. Role titles and role-potential lines go;
    # the findings and their hours stay, so every total still adds up.
    POOL_MIN = 2

    def pool_small_roles(departments)
      company_pool = []
      kept = departments.filter_map do |department|
        shared, solo = department["roles"].partition { |r| r["people"].to_i >= POOL_MIN }
        if solo.sum { |r| r["people"].to_i } >= POOL_MIN
          shared << pooled_role("Other roles", solo)
        else
          company_pool.concat(solo)
        end
        next if shared.empty?

        shared.sort_by! { |r| [-r["hours_max"].to_i, r["title"]] }
        department.merge("roles" => shared).merge(range(shared.flat_map { |r| r["findings"] }))
      end
      if company_pool.any?
        # Across the company the department goes too: a department of one names
        # its person as surely as a role does.
        role = pooled_role("Roles across the company", company_pool, drop_department: true)
        kept << { "name" => "Across the company", "roles" => [role], "pooled" => true }.merge(range(role["findings"]))
      end
      kept
    end

    def pooled_role(title, roles, drop_department: false)
      findings = roles.flat_map { |r| r["findings"] }.map do |f|
        f.merge("role" => nil).merge(drop_department ? { "department" => nil } : {})
      end
      findings.sort_by! { |f| [-f["hours_max"].to_i, f["title"]] }
      { "title" => title, "people" => roles.sum { |r| r["people"].to_i }, "findings" => findings,
        "potential" => nil, "pooled" => true }.merge(range(findings))
    end

    # Confirmed shared work, by finding: the cluster it is in, and for a finding
    # synthesis set aside as the same execution as another, which one stands.
    def shared_work
      @shared_work ||= begin
        engagement = @company.current_engagement
        clusters = engagement ? ProcessCluster.current.approved.where(engagement: engagement)
                                              .includes(:members, :effort_normalization).to_a : []
        counted_in = {}
        clusters.each do |cluster|
          Array(cluster.effort_normalization&.overlap_adjustments).each do |adjustment|
            next unless adjustment["removed_item_id"] && adjustment["kept_item_id"]

            counted_in[adjustment["removed_item_id"]] = adjustment["kept_item_id"]
          end
        end
        { clusters: clusters, cluster_of: clusters.flat_map { |c| c.finding_ids.map { |id| [id, c] } }.to_h,
          counted_in: counted_in }
      end
    end

    # Only when both findings are shown: counting a finding "with" one the
    # client can't see would hide its hours altogether.
    def counted_once(finding)
      cluster = shared_work[:cluster_of][finding.id]
      return {} unless cluster

      kept = shown_findings.find { |f| f.id == shared_work[:counted_in][finding.id] }
      { "shared_work" => cluster.name, "shared_work_key" => cluster.cluster_key, "deduplication_applied" => true,
        "counted_in" => kept && { "id" => kept.id, "title" => kept.display_title.to_s.upcase_first } }.compact
    end

    # Where else the same shared work appears, as the report shows it: read after
    # pooling, so a row pooled across the company carries no department here
    # either.
    def attach_shared_work(departments)
      rows = departments.flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }
      rows.group_by { |r| r["shared_work_key"] }.except(nil).each_value do |group|
        group.each do |row|
          row["also_in"] = (group - [row]).select { |o| o["department"].present? && o["department"] != row["department"] }
                                         .map { |o| o.slice("id", "title", "department") }
        end
      end
    end

    def range(findings)
      quantified = findings.select { |f| f["hours_min"] && f["counted_in"].nil? }
      return { "hours_min" => nil, "hours_max" => nil } if quantified.empty?

      out = { "hours_min" => quantified.sum { |f| f["hours_min"] }, "hours_max" => quantified.sum { |f| f["hours_max"] } }
      valued = quantified.select { |f| f["value_min"] }
      if valued.any?
        out.merge!("value_min" => valued.sum { |f| f["value_min"] }, "value_max" => valued.sum { |f| f["value_max"] },
                   "currency" => valued.first["currency"])
      end
      out
    end

    # Capacity, valued: the finding's hours at a benchmark loaded rate for the role
    # family (its department, or "default") — never anyone's salary. Rounded
    # outward to the hundred, like the hours. Nothing when no rate is agreed.
    def value_for(finding)
      return {} unless finding.hours?

      rate = rate_for(finding.department)
      return {} unless rate

      (@rates_used ||= Set.new) << rate
      { "value_min" => (finding.annual_hours_min * rate.hourly_rate_min / 100).floor * 100,
        "value_max" => (finding.annual_hours_max * rate.hourly_rate_max / 100).ceil * 100,
        "currency" => rate.currency }
    end

    def rate_for(department)
      @rates ||= {}
      key = department.to_s.strip.downcase
      return @rates[key] if @rates.key?(key)

      @rates[key] = BenchmarkRate.for(key) || BenchmarkRate.for("default")
    end
  end
end
