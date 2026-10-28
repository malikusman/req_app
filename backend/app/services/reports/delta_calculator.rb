# frozen_string_literal: true

module Reports
  class DeltaCalculator
    def self.call(company:, previous_report: nil)
      new(company: company, previous_report: previous_report).call
    end

    def initialize(company:, previous_report: nil)
      @company = company
      @previous_report = previous_report
    end

    def call
      return findings_delta if findings_era?

      current_signals = @company.company_signals.pluck(:id, :label, :strength)
      current_patterns = @company.patterns.pluck(:id, :title)
      current_recs = @company.recommendations.published.pluck(:id, :title)

      return empty_delta if @previous_report.blank?

      prev = @previous_report.report_snapshot
      prev_signal_ids = Set.new(prev.dig("signals")&.map { |s| s["id"] } || [])
      prev_pattern_ids = Set.new(prev.dig("patterns")&.map { |p| p["id"] } || [])
      prev_rec_ids = Set.new(prev.dig("recommendations")&.map { |r| r["id"] } || [])

      new_signals = current_signals.reject { |id, _, _| prev_signal_ids.include?(id) }
      new_patterns = current_patterns.reject { |id, _| prev_pattern_ids.include?(id) }
      new_recs = current_recs.reject { |id, _| prev_rec_ids.include?(id) }

      strengthened = current_signals.select do |id, label, strength|
        prev_signal = prev.dig("signals")&.find { |s| s["id"] == id }
        prev_signal && strength > (prev_signal["strength"] || 0) + 0.1
      end.map { |_, label, strength| { "label" => label, "strength" => strength } }

      summary_parts = []
      summary_parts << "#{new_patterns.size} new pattern#{'s' if new_patterns.size != 1}" if new_patterns.any?
      summary_parts << "#{new_recs.size} new recommendation#{'s' if new_recs.size != 1}" if new_recs.any?
      summary_parts << "#{new_signals.size} new signal#{'s' if new_signals.size != 1}" if new_signals.any?

      {
        "new_signals" => new_signals.map { |id, label, strength| { "id" => id, "label" => label, "strength" => strength } },
        "new_patterns" => new_patterns.map { |id, title| { "id" => id, "title" => title } },
        "new_recommendations" => new_recs.map { |id, title| { "id" => id, "title" => title } },
        "strengthened_signals" => strengthened,
        "summary" => summary_parts.any? ? "#{summary_parts.join(', ')} since Report v#{@previous_report.version}" : "No major changes since previous report"
      }
    end

    private

    # "What's new in this version" (Doc 15 §4.0, §13.1): the findings added,
    # updated and superseded since the version before, and the departments newly
    # covered. Read from the findings as the report shows them, so a finding held
    # back for review is not announced, and one that leaves the report is marked
    # superseded with the reason, never dropped silently.
    def findings_delta
      return empty_delta if @previous_report.blank?

      before = rows(@previous_report.report_snapshot&.dig("findings"))
      after = rows(current_findings)
      added = after.keys - before.keys
      kept = after.keys & before.keys
      gone = before.keys - after.keys

      updated = kept.filter_map do |id|
        change = change_between(before[id], after[id])
        entry(after[id]).merge("change" => change) if change
      end
      changes = {
        "added" => added.map { |id| entry(after[id]) },
        "updated" => updated,
        "superseded" => superseded(gone.map { |id| before[id] }),
        "new_departments" => departments(current_findings) - departments(@previous_report.report_snapshot&.dig("findings"))
      }
      empty_delta.merge("findings" => changes, "summary" => findings_summary(changes))
    end

    # A report built after findings existed — before them, the delta is still about
    # signals.
    def findings_era?
      current_findings["totals"].to_h["findings"].to_i.positive? ||
        @previous_report&.report_snapshot&.dig("findings", "totals", "findings").to_i.positive?
    end

    def current_findings
      @current_findings ||= Findings::ForReport.call(company: @company)
    end

    def rows(view)
      return {} unless view.is_a?(Hash)

      Array(view["departments"]).flat_map { |d| Array(d["roles"]).flat_map { |r| Array(r["findings"]) } }.index_by { |f| f["id"] }
    end

    def departments(view)
      return [] unless view.is_a?(Hash)

      # A pool across the company has no department of its own to announce.
      Array(view["departments"]).reject { |d| d["pooled"] }.map { |d| d["name"] }
    end

    def entry(row)
      row.slice("id", "title", "department", "hours_min", "hours_max")
    end

    def change_between(was, now)
      if [was["hours_min"], was["hours_max"]] != [now["hours_min"], now["hours_max"]]
        "hours #{hours(now) || 'not yet quantified'}, were #{hours(was) || 'not quantified'}"
      elsif %w[title what_happens_now friction].any? { |k| was[k] != now[k] }
        "reworded on review"
      end
    end

    def hours(row)
      return nil unless row["hours_min"]

      row["hours_min"] == row["hours_max"] ? row["hours_min"].to_s : "#{row['hours_min']}–#{row['hours_max']}"
    end

    def superseded(rows)
      return [] if rows.empty?

      current = @company.findings.where(id: rows.map { |r| r["id"] }).includes(:merged_into).index_by(&:id)
      rows.map do |row|
        finding = current[row["id"]]
        reason = case finding&.status
                 when "merged" then "merged into “#{finding.merged_into&.display_title.to_s.upcase_first}”"
                 when "hidden", nil then "withdrawn on review"
                 else "held for review"
                 end
        entry(row).merge("reason" => reason)
      end
    end

    def findings_summary(changes)
      parts = []
      { "added" => "new", "updated" => "updated", "superseded" => "superseded" }.each do |key, word|
        n = changes[key].size
        parts << "#{n} #{word} #{'finding'.pluralize(n)}" if n.positive?
      end
      fresh = changes["new_departments"]
      parts << "#{fresh.map { |d| ReportsHelper.report_department_label(d) }.to_sentence} newly covered" if fresh.any?
      return "No changes to the findings since Report v#{@previous_report.version}" if parts.empty?

      "#{parts.to_sentence.upcase_first} since Report v#{@previous_report.version}"
    end

    def empty_delta
      {
        "new_signals" => [],
        "new_patterns" => [],
        "new_recommendations" => [],
        "strengthened_signals" => [],
        "summary" => "Initial discovery report"
      }
    end
  end
end
