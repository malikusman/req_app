# frozen_string_literal: true

module ReportsHelper
  CATEGORY_BY_SIGNAL_TYPE = {
    "manual_process" => "cat-process",
    "time_sink" => "cat-process",
    "tool_dependency" => "cat-tooling",
    "approval_bottleneck" => "cat-people",
    "communication" => "cat-people",
    "data_silo" => "cat-data"
  }.freeze

  CATEGORY_LABELS = {
    "cat-process" => "Process",
    "cat-tooling" => "Tooling",
    "cat-people" => "People",
    "cat-data" => "Data"
  }.freeze

  CATEGORY_COLORS = {
    "cat-process" => "#1F40FF",
    "cat-tooling" => "#00A9F4",
    "cat-people" => "#E6338A",
    "cat-data" => "#14B8A6"
  }.freeze

  CATEGORY_CYCLE = %w[cat-process cat-tooling cat-people cat-data].freeze

  READINESS_BAR_META = {
    "employees_interviewed" => { label: "Employee coverage", cat: "", target: 3 },
    "departments_represented" => { label: "Department spread", cat: "cat-tooling", target: 2 },
    "confirmed_patterns" => { label: "Pattern confidence", cat: "cat-people", target: 1 },
    "multimodal_contributions" => { label: "Multimodal evidence", cat: "cat-data", target: 1 },
    "insights_count" => { label: "Insights captured", cat: "cat-process", target: 10 }
  }.freeze

  def report_reset_page!
    @_report_page = 0
  end

  def report_next_page
    @_report_page = (@_report_page || 0) + 1
    format("%02d", @_report_page)
  end

  def report_category_class(signal_type)
    CATEGORY_BY_SIGNAL_TYPE.fetch(signal_type.to_s, "cat-process")
  end

  def report_pattern_category_class(title)
    digest = title.to_s.each_byte.sum
    CATEGORY_CYCLE[digest % CATEGORY_CYCLE.size]
  end

  def report_category_label(css_class)
    CATEGORY_LABELS.fetch(css_class.to_s, "Process")
  end

  def report_category_color(css_class)
    CATEGORY_COLORS.fetch(css_class.to_s, "#1F40FF")
  end

  def report_brand_footer(company_name)
    "Req · #{company_name} Discovery Report"
  end

  def report_pct(value)
    v = value.to_f
    v = v * 100 if v <= 1.0
    [[v.round, 0].max, 100].min
  end

  def report_has_delta?(delta)
    delta = delta || {}
    summary = delta["summary"].to_s
    summary.present? && summary != "Initial discovery report"
  end

  def report_priority_pill(priority)
    case priority.to_s.downcase
    when "high" then "high"
    when "low" then "low"
    else "med"
    end
  end

  def report_priority_label(priority)
    case report_priority_pill(priority)
    when "high" then "High priority"
    when "low" then "Low priority"
    else "Medium priority"
    end
  end

  def report_donut_svg(pct, color)
    pct = [[pct.to_i, 0].max, 100].min
    rest = 100 - pct
    <<~SVG.html_safe
      <svg width="64" height="64" viewBox="0 0 42 42" aria-hidden="true">
        <circle cx="21" cy="21" r="15.9" fill="none" stroke="#EFF3F7" stroke-width="5"/>
        <circle cx="21" cy="21" r="15.9" fill="none" stroke="#{color}" stroke-width="5"
          stroke-dasharray="#{pct} #{rest}" stroke-dashoffset="25"
          transform="rotate(-90 21 21)" stroke-linecap="round"/>
        <text x="21" y="24" text-anchor="middle" font-size="9" font-weight="700"
          fill="#051C2C" font-family="Inter">#{pct}</text>
      </svg>
    SVG
  end

  def report_readiness_bars(breakdown)
    (breakdown || {}).filter_map do |key, raw|
      meta = READINESS_BAR_META[key.to_s]
      next unless meta

      target = meta[:target].to_f
      pct = target.positive? ? [[(raw.to_f / target) * 100, 100].min, 0].max.round : 0
      {
        label: meta[:label],
        cat: meta[:cat],
        pct: pct,
        display: pct
      }
    end
  end

  def report_toc_entries(snapshot)
    entries = []
    n = 0
    add = lambda do |title, description, rule|
      n += 1
      entries << { n: format("%02d", n), title: title, description: description, rule: rule }
    end

    add.call("Executive summary", "The headline story in one read", "rule-blue") if snapshot["executive_summary"].present?
    if snapshot.dig("readiness", "score").present?
      add.call("Readiness", "Score and its weighted breakdown", "rule-blue")
    end
    participation = snapshot["participation"] || {}
    if participation["invited"].to_i.positive? || participation["completed"].to_i.positive?
      add.call("Participation", "Invited, started, completed", "rule-teal")
    end
    add.call("What changed", "Delta versus the previous version", "rule-teal") if report_has_delta?(snapshot["delta_from_previous"])
    add.call("Signals", "Recurring pain points with evidence", "rule-magenta") if Array(snapshot["signals"]).any?
    add.call("Patterns", "Cross-team themes and confidence", "rule-magenta") if Array(snapshot["patterns"]).any?
    add.call("Recommendations", "Prioritized actions, catalog-matched", "rule-blue") if Array(snapshot["recommendations"]).any?
    add.call("Supporting media & method", "Evidence base and how we measured", "rule-teal")
    entries
  end

  def report_signal_excerpt(signal)
    excerpts = Array(signal["source_excerpts"])
    first = excerpts.first
    return nil if first.blank?

    if first.is_a?(Hash)
      text = first["excerpt"] || first["text"] || first["body"]
      return text.presence
    end
    first.to_s.presence
  end

  def report_catalog_match(recommendation)
    matches = Array(recommendation["catalog_matches"])
    return nil if matches.blank?

    first = matches.first
    if first.is_a?(Hash)
      first["name"] || first["title"] || first["label"]
    else
      first.to_s
    end
  end

  def report_source_caption(company_name, version: nil)
    ver = version.present? ? "v#{version}" : "snapshot"
    "Source: Req discovery #{ver} · #{company_name}"
  end

  def report_priority_matrix_svg(recommendations)
    points = []
    Array(recommendations).each_with_index do |rec, i|
      pill = report_priority_pill(rec["priority"])
      impact = case pill
               when "high" then 80 - (i % 3) * 5
               when "low" then 45
               else 65 - (i % 3) * 4
               end
      feas = case pill
             when "high" then 70 + (i % 3) * 5
             when "low" then 55
             else 60 + (i % 3) * 6
             end
      x = 40 + (feas / 100.0) * 320
      y = 300 - (impact / 100.0) * 260
      color = { "high" => "#E6338A", "med" => "#00A9F4", "low" => "#8896A2" }[pill]
      label = rec["title"].to_s.split.first(2).join(" ")
      points << %(<circle cx="#{x.round}" cy="#{y.round}" r="7" fill="#{color}"/>)
      points << %(<text x="#{x.round + 11}" y="#{y.round + 3}" font-size="8" fill="#051C2C" font-family="Inter">#{ERB::Util.html_escape(label)}</text>)
    end

    <<~SVG.html_safe
      <svg viewBox="0 0 420 330" xmlns="http://www.w3.org/2000/svg" width="100%" aria-hidden="true">
        <line x1="40" y1="300" x2="380" y2="300" stroke="#051C2C" stroke-width="1"/>
        <line x1="40" y1="20" x2="40" y2="300" stroke="#051C2C" stroke-width="1"/>
        <line x1="210" y1="20" x2="210" y2="300" stroke="#D6DEE6" stroke-dasharray="3 3"/>
        <line x1="40" y1="160" x2="380" y2="160" stroke="#D6DEE6" stroke-dasharray="3 3"/>
        <text x="210" y="322" text-anchor="middle" font-size="8" fill="#5A6B78" font-family="Inter">Feasibility →</text>
        <text x="18" y="160" text-anchor="middle" font-size="8" fill="#5A6B78" font-family="Inter" transform="rotate(-90 18 160)">Impact →</text>
        #{points.join}
      </svg>
    SVG
  end
end
