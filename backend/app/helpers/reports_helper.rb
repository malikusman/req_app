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

  # --- Reviewer section overrides (applied at regenerate time) ---
  def report_section_hidden?(snapshot, key)
    Array(snapshot.dig("section_overrides", "hidden")).include?(key.to_s)
  end

  def report_section_edit(snapshot, key)
    edits = snapshot.dig("section_overrides", "edits")
    edits.is_a?(Hash) ? edits[key.to_s] : nil
  end

  # Custom sections a reviewer added, anchored after a given built-in section
  # (or, when anchor is blank, only when `anchor` itself is nil — i.e. trailing).
  def report_custom_sections(snapshot, after: nil)
    Array(snapshot.dig("section_overrides", "custom")).select do |c|
      c["anchor_section"].presence == after
    end.sort_by { |c| c["position"].to_i }
  end

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
    s = s.gsub(/\s+\./, ".").gsub(/\.(?:\s*\.)+/, ".") # collapse orphan " . ." artifacts
    s.sub(/\A[;,.\s]+/, "").presence
  end

  # Reverse the stored revenue enum ("10m_50m") back to the client-facing band
  # ("$10M–$50M"). Falls back to a light humanize for unmapped values.
  REVENUE_BAND_LABELS = {
    "under_500k" => "<$500K",
    "500k_2m" => "$500K–$2M",
    "2m_10m" => "$2M–$10M",
    "10m_50m" => "$10M–$50M",
    "50m_plus" => "$50M+"
  }.freeze
  def report_revenue_band_label(value)
    v = value.to_s.strip
    return nil if v.blank?

    REVENUE_BAND_LABELS[v.downcase] || v.tr("_", " ").upcase
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

  # Maps a TOC title to the section_key a reviewer can hide, so a hidden section
  # drops out of the contents page too.
  TOC_TITLE_TO_KEY = {
    "Executive summary" => "executive_summary", "Readiness" => "readiness",
    "Company context" => "company_context", "Participation" => "participation",
    "What changed" => "delta", "Signals" => "signals", "Patterns" => "patterns",
    "Implications" => "patterns", "Recommendations" => "recommendations",
    "Roadmap" => "roadmap", "Opportunities" => "opportunities",
    "Capabilities & evidence" => "tools_catalog", "Supporting media" => "supporting_media",
    "Methodology" => "methodology"
  }.freeze

  def report_toc_entries(snapshot)
    entries = []
    n = 0
    add = lambda do |title, description, rule|
      key = TOC_TITLE_TO_KEY[title]
      next if key && report_section_hidden?(snapshot, key)

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
    add.call("Roadmap", "Sequenced now / next / later", "rule-blue") if snapshot["roadmap"].present?
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

  # Human-readable, de-duplicated media-evidence labels. Prefer the attachment's
  # semantic type ("screen_recording") over the internal source enum
  # ("media_attachment") that used to leak into the client PDF.
  def report_multimodal_labels(signal)
    Array(signal["multimodal_evidence"]).filter_map do |item|
      raw = if item.is_a?(Hash)
        item["attachment_type"] || item["type"] || item["label"] || item["kind"] || item["source"]
      else
        item
      end
      report_media_type_label(raw)
    end.uniq.first(4)
  end

  MEDIA_SOURCE_FALLBACK = { "media_attachment" => "Media attachment" }.freeze
  def report_media_type_label(raw)
    v = raw.to_s.strip
    return nil if v.blank?

    MEDIA_SOURCE_FALLBACK[v.downcase] || v.tr("_", " ").split.map(&:capitalize).join(" ")
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
  # Department × friction-category heatmap, built from real signal data
  # (departments each signal touches, weighted by strength). Returns "" when
  # there isn't enough dimensional data to be meaningful.
  def report_department_heatmap_svg(signals)
    rows = {}     # dept_key => { category => summed strength }
    labels = {}   # dept_key => first-seen display label
    Array(signals).each do |s|
      cat = report_category_class(s["signal_type"])
      strength = s["strength"].to_f
      strength /= 100.0 if strength > 1.0
      Array(s["departments"]).reject(&:blank?).each do |dept|
        key = dept.to_s.downcase.strip
        labels[key] ||= dept.to_s.strip
        rows[key] ||= Hash.new(0.0)
        rows[key][cat] += strength
      end
    end
    return "".html_safe if rows.size < 2

    cats = CATEGORY_CYCLE
    max = rows.values.flat_map(&:values).max.to_f
    max = 1.0 if max <= 0

    cell = 46
    left = 130
    top = 30
    width = left + cats.size * cell + 20
    height = top + rows.size * cell + 30

    svg = +%(<svg viewBox="0 0 #{width} #{height}" width="100%" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">)
    cats.each_with_index do |cat, ci|
      x = left + ci * cell + cell / 2
      svg << %(<text x="#{x}" y="#{top - 10}" text-anchor="middle" font-size="8" fill="#5A6B78" font-family="Inter">#{report_category_label(cat)}</text>)
    end
    rows.each_with_index do |(dept_key, catmap), ri|
      y = top + ri * cell
      dept = labels[dept_key]
      svg << %(<text x="#{left - 8}" y="#{y + cell / 2 + 3}" text-anchor="end" font-size="8" fill="#051C2C" font-family="Inter">#{ERB::Util.html_escape(dept.to_s.truncate(16))}</text>)
      cats.each_with_index do |cat, ci|
        x = left + ci * cell
        intensity = (catmap[cat] / max).clamp(0.0, 1.0)
        # Visual restraint: ONE accent, intensity carries the signal — so a hotter
        # cell reads as more friction, not just a different colour. (Distinct hues
        # per column made intensities incomparable across columns.)
        opacity = (0.06 + intensity * 0.94).round(2)
        svg << %(<rect x="#{x}" y="#{y}" width="#{cell - 4}" height="#{cell - 4}" rx="3" fill="#1F40FF" fill-opacity="#{opacity}"/>)
      end
    end
    svg << "</svg>"
    svg.html_safe
  end

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
