# frozen_string_literal: true

module Reports
  # Extracts quantified, business-relevant metrics from the company's REAL
  # evidence (ready-document text + interview answers) so the report can lead
  # with numbers a CEO recognises — "11–14 days vs an 8-day target", "1 in 5
  # invoices fail the three-way match" — instead of internal model scores.
  #
  # Deterministic and grounded by construction: every metric carries the source
  # snippet it came from; nothing is invented. Zero LLM calls, so no latency and
  # no hallucination risk. Returns [] when the evidence has no quantified facts.
  class MetricExtractor
    MAX_METRICS = 6
    SNIPPET_MAX = 140

    # Units that make a number a *business* metric (excludes bare integers,
    # dates and document IDs).
    UNIT = /(?:business\s+days|days?|hours?|weeks?|months?|%|percent)/i
    CURRENCY = /AED\s?[\d,]+(?:\.\d+)?(?:\s?[KkMm])?/
    RATIO = /\b1\s+in\s+\d+\b/i
    NUMBER = /\d+(?:,\d{3})*(?:\.\d+)?/
    RANGE = /#{NUMBER}\s?(?:[–-]|to)\s?#{NUMBER}/
    VALUE = /(?:#{CURRENCY}|(?:#{RANGE}|#{NUMBER})\s*#{UNIT}|#{RANGE}|#{RATIO}|#{NUMBER}\s?%)/
    # Most "so-what" first: a ratio or percent beats a bare duration when a
    # sentence carries several numbers.
    HEADLINE_PRIORITY = [RATIO, /#{NUMBER}\s?%/, CURRENCY, /(?:#{RANGE}|#{NUMBER})\s*#{UNIT}/].freeze

    # Reject clauses that are really identifiers/dates, not measurements.
    NOISE = /\b(?:19|20)\d{2}[-\/]\d{1,2}[-\/]\d{1,2}\b|\bGL-[A-Z]+-[A-Z0-9-]+\b|Document ID|Effective:|Version:/i

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      units = gather_evidence
      metrics = []
      units.each do |unit|
        metrics.concat(table_metrics(unit))
        metrics.concat(sentence_metrics(unit))
      end
      dedupe_and_rank(metrics)
    end

    private

    # [{ text:, source: }] — real document chunks and interview answers only.
    def gather_evidence
      evidence = []
      @company.documents.where(status: "ready").includes(:document_chunks).find_each do |doc|
        label = "Document: #{doc.filename}"
        doc.document_chunks.order(:chunk_index).limit(12).each do |chunk|
          evidence << { text: chunk.content.to_s, source: label }
        end
        summary = doc.insights_preview.is_a?(Hash) ? doc.insights_preview["summary"].to_s : ""
        evidence << { text: summary, source: label } if summary.present?
      end
      Message.joins(:conversation)
             .where(conversations: { company_id: @company.id }, direction: "inbound")
             .where.not(body: [nil, ""])
             .limit(200)
             .pluck(:body)
             .each { |body| evidence << { text: body, source: "Interview" } }
      evidence
    end

    # KPI table rows shaped "Label | target | actual" — the highest-value form,
    # since it already carries the "so what" (a gap against target).
    def table_metrics(unit)
      unit[:text].to_s.each_line.filter_map do |line|
        next unless line.include?("|")

        cells = line.split("|").map(&:strip).reject(&:blank?)
        next if cells.size < 3

        label = cells.first
        next if label.blank? || label.match?(/#{NUMBER}/) # header/label must be text (skips the AED threshold matrix)
        next if label.match?(NOISE)

        numeric = cells[1..].select { |c| c.match?(VALUE) }
        next if numeric.size < 2

        target = numeric[-2]
        actual = numeric[-1]
        {
          "headline" => actual.truncate(24),
          "label" => label.truncate(60),
          "comparison" => "target #{target}".truncate(28),
          "direction" => "negative",
          "source" => unit[:source]
        }
      end
    end

    # Quantified pain sentences (durations, currency, %, ratios) with their clause.
    def sentence_metrics(unit)
      sentences = unit[:text].to_s.split(/(?<=[.!?])\s+|\n/)
      sentences.filter_map do |sentence|
        s = sentence.strip.gsub(/\s+/, " ")
        next if s.length < 12 || s.length > 220
        next if s.include?("|")            # handled by table_metrics
        next if s.match?(NOISE)

        headline = HEADLINE_PRIORITY.filter_map { |re| s[re] }.first&.strip
        next unless headline
        next unless headline.match?(/#{UNIT}|#{CURRENCY}|#{RATIO}|%/) # require a real unit, not a bare range

        {
          "headline" => headline.truncate(24),
          "label" => humanize_clause(s, headline),
          "comparison" => nil,
          "direction" => negative?(s) ? "negative" : "neutral",
          "source" => unit[:source]
        }
      end
    end

    # Strip the number out of the clause to leave the "what it measures" phrase.
    def humanize_clause(sentence, headline)
      phrase = sentence.sub(headline, "").gsub(/\s+/, " ").strip
      phrase = phrase.sub(/\A[-–—•,:;]\s*/, "").sub(/[,:;]\s*\z/, "")
      phrase.presence&.truncate(SNIPPET_MAX) || sentence.truncate(SNIPPET_MAX)
    end

    def negative?(sentence)
      sentence.match?(/delay|wait|fail|bottleneck|late|error|slow|exception|aging|rework|manual|duplicat|over\s?\d/i)
    end

    # Prefer target/actual gaps, then ratios/percentages, then negatives. Rank
    # first, then dedupe so the cleanest phrasing of each fact survives.
    def dedupe_and_rank(metrics)
      ranked = metrics.sort_by do |m|
        rich = m["headline"].to_s.match?(/#{RATIO}|%/) ? 0 : 1 # ratios/percentages carry the most "so what"
        [m["comparison"] ? 0 : 1, rich, m["direction"] == "negative" ? 0 : 1, -m["label"].to_s.length]
      end

      seen = {}
      ranked.each do |m|
        # A distinctive value (ratio/currency/percent) IS the fact's identity, so
        # collapse different phrasings of it; otherwise key on value + label.
        identity = m["headline"].to_s.downcase.gsub(/\s+/, "")
        key = identity.match?(/1in\d+|aed|%/) ? identity : "#{identity}|#{m['label'].to_s.downcase[0, 24]}"
        seen[key] ||= m
      end
      seen.values.first(MAX_METRICS)
    end
  end
end
