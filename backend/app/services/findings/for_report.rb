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
      departments.sort_by! { |d| [-d["hours_max"].to_i, d["name"]] }

      all = departments.flat_map { |d| d["roles"] }.flat_map { |r| r["findings"] }
      {
        "departments" => departments,
        "totals" => {
          "findings" => all.size,
          "quantified" => all.count { |f| f["hours_min"] },
          "roles" => departments.sum { |d| d["roles"].size },
          "departments" => departments.size,
          "people" => shown.map(&:employee_id).compact.uniq.size
        }.merge(range(all)),
        "delays" => all.select { |f| f["effort_type"] == "waiting" }.map do |f|
          f.slice("title", "role", "department", "duration")
        end,
        "withheld" => @withheld_count,
        "basis" => AnnualHours::BASIS
      }
    end

    # What each role's people said they would do with more time, for the report
    # writer to turn into one line about the role. Deliberately NOT part of the
    # snapshot: it is closer to what someone said than a finding is, and the
    # snapshot is served to the client over the API.
    def role_potential_notes
      shown = shown_findings
      shown.group_by { |f| [f.department.presence || "Other", f.role_title.presence || "Role not recorded"] }
           .filter_map do |(department, role), items|
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
          "frequency" => f.frequency_as_said,
          "duration" => f.duration_as_said,
          "effort_type" => f.effort_type,
          "hours_min" => f.annual_hours_min,
          "hours_max" => f.annual_hours_max,
          "people" => people,
          "confidence" => f.confidence,
          "basis" => f.basis
        }
      end
      findings.sort_by! { |f| [-f["hours_max"].to_i, f["title"]] }
      people = items.flat_map { |f| [f.employee_id] + Array(merged_into[f.id]) }.compact.uniq.size
      { "title" => title, "people" => people, "findings" => findings, "potential" => nil }.merge(range(findings))
    end

    def range(findings)
      quantified = findings.select { |f| f["hours_min"] }
      return { "hours_min" => nil, "hours_max" => nil } if quantified.empty?

      { "hours_min" => quantified.sum { |f| f["hours_min"] }, "hours_max" => quantified.sum { |f| f["hours_max"] } }
    end
  end
end
