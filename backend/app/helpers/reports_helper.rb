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
    "insights_count" => { label: "Insights captured", cat: "cat-process", target: 10 },
    "ready_documents" => { label: "Ready documents", cat: "cat-process", target: 3 },
    "document_departments" => { label: "Document departments", cat: "cat-tooling", target: 1 }
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

  # Category from meaning, not a byte-hash of the title (which mislabeled
  # "Approval bottleneck" as "Data"). Falls back to a stable default.
  PATTERN_CATEGORY_KEYWORDS = {
    "cat-people" => %w[approval sign-off handoff hand-off communication coordination escalation stakeholder manager],
    "cat-tooling" => %w[tool system integration platform software erp crm spreadsheet legacy],
    "cat-data" => %w[data report reconcil duplicate entry silo visibility tracking record],
    "cat-process" => %w[process manual workflow bottleneck delay rework backlog cycle time step]
  }.freeze

  def report_pattern_category_class(title, signal_types: nil)
    types = Array(signal_types).map(&:to_s)
    mapped = types.filter_map { |t| CATEGORY_BY_SIGNAL_TYPE[t] }
    return mapped.first if mapped.any?

    t = title.to_s.downcase
    PATTERN_CATEGORY_KEYWORDS.each do |css, words|
      return css if words.any? { |w| t.include?(w) }
    end
    "cat-process"
  end

  def report_category_label(css_class)
    CATEGORY_LABELS.fetch(css_class.to_s, "Process")
  end

  def report_category_color(css_class)
    CATEGORY_COLORS.fetch(css_class.to_s, "#1F40FF")
  end

  def report_brand_footer(company_name, snapshot = nil)
    "Worktruth · #{company_name} #{report_kind_noun(snapshot || @_report_snapshot)} Report"
  end

  # "Baseline" for docs-only companies, "Discovery" once interviews contribute.
  def report_kind_noun(snapshot)
    kind = snapshot.is_a?(Hash) ? snapshot["report_kind"].to_s : ""
    kind == "baseline" ? "Baseline" : "Discovery"
  end

  # Plain-language band for a 0..1 (or 0..100) score. Consulting readers want
  # "High", not "0.58".
  def report_score_band(value)
    v = value.to_f
    v /= 100.0 if v > 1.0
    if v >= 0.66 then "High"
    elsif v >= 0.4 then "Medium"
    else "Low"
    end
  end
  alias report_strength_label report_score_band
  alias report_confidence_label report_score_band

  # Placeholder/example domains must never reach a client deliverable.
  PLACEHOLDER_URL_RE = /\A(https?:\/\/)?(www\.)?(example\.(com|org|net)|test\.|localhost|placeholder)/i
  def report_placeholder_url?(url)
    url.to_s.strip.match?(PLACEHOLDER_URL_RE)
  end

  # Strip internal match-debug fragments that leak into `why_it_fits`, e.g.
  # "Match basis: tag_match:manual_process; keyword_match:manual".
  def report_clean_reason(text)
    s = text.to_s.dup
    s = s.gsub(/match basis:.*?(?=(\.|\z))/i, "")
    s = s.gsub(/\b(tag_match|keyword_match|semantic_match|required_system|already_in_stack)\s*:\s*\S+/i, "")
    s = s.gsub(/[;,]\s*(?=[;,.]|\z)/, "").gsub(/\s{2,}/, " ").strip
    s.sub(/\A[;,.\s]+/, "").presence
  end

  # Humanize a firmographic enum; hide non-informative catch-alls.
  def report_industry_label(value)
    v = value.to_s.strip
    return nil if v.blank? || %w[other unknown n/a na none general].include?(v.downcase)

    v.tr("_", " ").split.map(&:capitalize).join(" ")
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

  def report_readiness_bars(breakdown, docs_first: false)
    preferred = if docs_first
                  %w[ready_documents document_departments confirmed_patterns multimodal_contributions]
                else
                  %w[employees_interviewed departments_represented confirmed_patterns multimodal_contributions ready_documents document_departments]
                end

    preferred.filter_map do |key|
      raw = (breakdown || {})[key]
      next if raw.nil?

      meta = READINESS_BAR_META[key]
      next unless meta

      target = meta[:target].to_f
      pct = target.positive? ? [[(raw.to_f / target) * 100, 100].min, 0].max.round : 0
      {
        label: meta[:label],
        cat: meta[:cat],
        pct: pct,
        display: pct,
        raw: raw.to_i,
        target: meta[:target],
        # Honest caption so an all-met breakdown doesn't read as a vanity 100%.
        caption: "#{raw.to_i} of #{meta[:target]} target"
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
    profile = snapshot.dig("company", "profile") || {}
    stack = Array(snapshot["client_stack"])
    kb = Array(snapshot["knowledge_base"])
    website = snapshot.dig("company", "website_url").presence || profile["website_url"].presence
    if profile.present? || stack.any? || kb.any? || website.present?
      add.call("Company context", "Firmographics, systems, and research", "rule-blue")
    end
    participation = snapshot["participation"] || {}
    if participation["invited"].to_i.positive? || participation["completed"].to_i.positive?
      add.call("Participation", "Invited, started, completed, by department", "rule-teal")
    end
    add.call("What changed", "Delta versus the previous version", "rule-teal") if report_has_delta?(snapshot["delta_from_previous"])
    add.call("Signals", "Recurring pain points with evidence", "rule-magenta") if Array(snapshot["signals"]).any?
    add.call("Patterns", "Cross-team themes and confidence", "rule-magenta") if Array(snapshot["patterns"]).any?
    add.call("Implications", "What the findings mean if left unaddressed", "rule-magenta") if Array(snapshot["implications"]).any?
    add.call("Recommendations", "Prioritized actions, catalog-matched", "rule-blue") if Array(snapshot["recommendations"]).any?
    add.call("Roadmap", "Sequenced now / next / later", "rule-blue") if snapshot.dig("narrative", "roadmap").present?
    add.call("Opportunities", "Published agentic ideas for this company", "rule-blue") if Array(snapshot["agentic_ideas"]).any?
    if Array(snapshot.dig("tools_catalog", "curated_matches")).any? || Array(snapshot["supporting_documents"]).any?
      add.call("Capabilities & evidence", "Catalog matches and supporting documents", "rule-teal")
    end
    add.call("Supporting media", "Multimodal evidence from discovery", "rule-teal") if Array(snapshot["supporting_media"]).any?
    add.call("Methodology", "How readiness and findings were measured", "rule-teal")
    entries
  end

  def report_signal_excerpt(signal)
    report_signal_excerpts(signal, limit: 1).first
  end

  def report_signal_excerpts(signal, limit: 3)
    Array(signal["source_excerpts"]).filter_map do |item|
      if item.is_a?(Hash)
        (item["excerpt"] || item["text"] || item["body"]).to_s.presence
      else
        item.to_s.presence
      end
    end.first(limit)
  end

  def report_multimodal_labels(signal)
    Array(signal["multimodal_evidence"]).filter_map do |item|
      if item.is_a?(Hash)
        (item["type"] || item["label"] || item["source"] || item["kind"]).to_s.presence
      else
        item.to_s.presence
      end
    end.first(4)
  end

  def report_catalog_match(recommendation)
    matches = report_catalog_matches(recommendation)
    matches.first&.dig("name")
  end

  def report_catalog_matches(recommendation)
    Array(recommendation["catalog_matches"]).filter_map do |m|
      next unless m.is_a?(Hash)

      {
        "name" => (m["name"] || m["title"] || m["label"]).to_s.presence,
        "vendor" => (m["vendor"]).to_s.presence,
        "score" => m["score"] || m[:score],
        "reason" => (m["reason"] || m["why_it_fits"]).to_s.presence
      }.tap { |h| h.compact! }
    end.select { |m| m["name"].present? }
  end

  def report_fit_score_label(score)
    return nil if score.nil?

    v = score.to_f
    pct = v <= 1.0 ? (v * 100).round : v.round
    "#{pct}% fit"
  end

  def report_source_caption(company_name, version: nil)
    ver = version.present? ? "v#{version}" : "snapshot"
    "Source: Worktruth discovery #{ver} · #{company_name}"
  end

  SECTION_LABELS = {
    "executive_summary" => "Executive summary",
    "readiness" => "Readiness",
    "participation" => "Participation",
    "signals" => "Signals",
    "patterns" => "Patterns",
    "recommendations" => "Recommendations",
    "supporting_media" => "Supporting media",
    "methodology" => "Methodology",
    "tools_catalog" => "Recommended capabilities"
  }.freeze

  def section_label(section_key)
    SECTION_LABELS.fetch(section_key.to_s) { section_key.to_s.humanize }
  end
  module_function :section_label

  # Impact/feasibility matrix plotted from REAL per-recommendation scores that
  # snapshot_builder derives from evidence weight and implementation effort.
  # Returns "" when those scores are absent, so we never fabricate positions.
  def report_priority_matrix_svg(recommendations)
    plottable = Array(recommendations).select do |rec|
      rec["impact_score"].present? && rec["feasibility_score"].present?
    end
    return "".html_safe if plottable.empty?

    points = []
    plottable.each do |rec|
      impact = [[rec["impact_score"].to_f, 0.0].max, 1.0].min * 100
      feas = [[rec["feasibility_score"].to_f, 0.0].max, 1.0].min * 100
      x = 40 + (feas / 100.0) * 320
      y = 300 - (impact / 100.0) * 260
      pill = report_priority_pill(rec["priority"])
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
