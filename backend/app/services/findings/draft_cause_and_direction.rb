# frozen_string_literal: true

module Findings
  # Drafts why each finding costs what it does, the kind of change that would
  # address it, and what must be true before that change can work (Doc 15 §4.5.2),
  # for the consultant to check on the Findings page.
  #
  # The model reads only what the finding already says — the task, what happens
  # now, what snags and how often — never the transcript. Every field it returns is
  # checked here: a figure, a quote, build detail or payroll language drops that
  # field rather than the whole draft. A finding is redrafted only when the wording
  # it was drafted from changes (Finding#draft_stale?), and the consultant's own
  # cause and direction are never touched.
  #
  # Fails safe: without a model, or on any error, findings keep what they had and
  # the report prints no cause or direction for them.
  class DraftCauseAndDirection
    include ProductNames

    BATCH = 12
    MAX_LENGTH = 300
    # "Lack of automation" names a missing fix, not why the work is slow.
    NOT_A_CAUSE = /\A(?:the )?(?:lack|absence) of\b|\bno (?:automat\w*|system|tool|software)\b/i
    # How a change is delivered, which is Stage 2's.
    DELIVERY = /\b(?:implement\w*|deploy\w*|install\w*)\b/i

    def self.call(findings:)
      new(findings: findings).call
    end

    def initialize(findings:)
      @findings = Array(findings).select(&:draft_stale?)
    end

    def call
      return [] if @findings.empty? || !enabled?

      client = Openai::Client.new
      return [] unless client.configured?

      @findings.each_slice(BATCH).flat_map { |batch| draft(client, batch) }
    end

    private

    def enabled?
      ENV.fetch("AI_REPORT_NARRATIVE", "true").to_s.downcase != "false"
    end

    def draft(client, batch)
      language = batch.first.company.locale.presence || "en"
      parsed = client.finding_causes(context: { "findings" => batch.map { |f| context(f) } }, language: language)
      drafts = Array(parsed.is_a?(Hash) ? parsed["findings"] : nil).select { |d| d.is_a?(Hash) }.index_by { |d| d["id"].to_i }
      batch.filter_map do |finding|
        item = drafts[finding.id]
        next unless item

        cause = clean(item["cause"])
        cause = nil if cause&.match?(NOT_A_CAUSE)
        direction = clean(item["direction"])
        direction = nil if direction&.match?(DELIVERY)
        finding.update!(
          cause: cause,
          cause_stated: cause.present? && item["cause_stated"] == true,
          intervention_type: direction && Finding::INTERVENTION_TYPES.key?(item["intervention_type"]) ? item["intervention_type"] : nil,
          direction: direction,
          # What must be true first only means something beside a direction.
          dependency: direction && clean(item["dependency"])&.then { |d| d.match?(DELIVERY) ? nil : d },
          draft_digest: finding.draft_inputs_digest
        )
        finding
      end
    rescue StandardError => e
      Rails.logger.warn("[Findings::DraftCauseAndDirection] left undrafted: #{e.class}: #{e.message}")
      []
    end

    def context(finding)
      {
        "id" => finding.id,
        "task" => finding.display_title,
        "role" => finding.role_title,
        "department" => finding.department,
        "what_happens_now" => finding.display_what_happens_now,
        "what_snags" => finding.display_friction,
        "how_often" => finding.display_frequency,
        "how_long" => finding.display_duration,
        "waiting" => finding.effective_effort_type == "waiting"
      }
    end

    # A sentence the report can print as it stands, or nothing.
    def clean(text)
      sentence = text.to_s.squish
      return nil if sentence.blank? || sentence.length > MAX_LENGTH
      return nil if sentence.match?(/\d/) || sentence.match?(/["“”]/)
      return nil if [Reports::Critic::BUILD, Reports::Critic::PAYROLL, Reports::Critic::FIRST_PERSON].any? { |p| sentence.match?(p) }
      return nil if names_a_product?(sentence)

      sentence
    end
  end
end
