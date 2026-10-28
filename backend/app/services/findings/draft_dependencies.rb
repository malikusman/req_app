# frozen_string_literal: true

module Findings
  # Drafts which findings must be addressed before which (Doc 15 §4.5.2,
  # "Dependencies"), across the company, for the consultant to keep or remove.
  #
  # Only a company-wide view can see that the leave balance sheet has to be right
  # before leave requests can be answered faster, so this is one model call over
  # every finding the report shows. The model returns ids; code decides what
  # stands:
  #   - only findings the report shows — a link to one held back for review would
  #     reveal it — and never a finding to itself;
  #   - a link to a merged finding follows it to the one it was merged into;
  #   - the link must be grounded: the earlier finding's own work — its task or
  #     cause — is named in what the later one needs first, or in its cause or
  #     direction. System names and generic words do not count, so "both use the
  #     ERP" never links customer orders to supplier price updates;
  #   - at most MAX_PER_FINDING links each, in the order the model gave them;
  #   - never a loop: a link that would close one is dropped.
  #
  # Fails safe: without a model, or on any error, every finding keeps the links it
  # had. The consultant's own links (consultant_depends_on_ids) are never touched.
  class DraftDependencies
    MAX_PER_FINDING = 2

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      shown = @company.findings.live.order(:id).to_a.reject(&:needs_review?)
      return {} if shown.size < 2 || !enabled?

      client = Openai::Client.new
      return {} unless client.configured?

      parsed = client.finding_dependencies(context: { "findings" => shown.map { |f| context(f) } },
                                           language: @company.locale.presence || "en")
      links = sound_links(parsed, shown)
      Finding.transaction do
        shown.each { |f| f.update!(depends_on_ids: links.fetch(f.id, [])) if f.depends_on_ids != links.fetch(f.id, []) }
      end
      links
    rescue StandardError => e
      Rails.logger.warn("[Findings::DraftDependencies] kept the existing links: #{e.class}: #{e.message}")
      {}
    end

    private

    def enabled?
      ENV.fetch("AI_REPORT_NARRATIVE", "true").to_s.downcase != "false"
    end

    def context(finding)
      {
        "id" => finding.id,
        "task" => finding.display_title,
        "role" => finding.role_title,
        "department" => finding.department,
        "cause" => finding.display_cause,
        "direction" => finding.display_direction,
        "must_be_true_first" => finding.display_dependency,
        "waiting" => finding.effective_effort_type == "waiting"
      }
    end

    # Whether `later`'s own words name the work `earlier` is about.
    def grounded?(later, earlier)
      needs = Words.of([later.display_dependency, later.display_cause, later.display_direction].join(" "), ignore: systems)
      about = Words.of([earlier.display_title, earlier.area, earlier.display_cause].join(" "), ignore: systems)
      (needs & about).any?
    end

    # The client's systems are shared by most findings, so naming one ties nothing.
    def systems
      @systems ||= (Array(@company.company_profile["tools"]) + %w[erp sap nav excel outlook email whatsapp portal sheet
                                                                spreadsheet power]).map(&:to_s)
    end

    # { finding id => [ids it depends on] }, holding only links that stand.
    def sound_links(parsed, shown)
      by_id = shown.index_by(&:id)
      shown_ids = by_id.keys.to_set
      merged = @company.findings.where(status: "merged").pluck(:id, :merged_into_id).to_h
      # The consultant's links count when looking for a loop: a draft must not
      # close one through a link they made.
      edges = shown.to_h { |f| [f.id, Array(f.consultant_depends_on_ids)] }
      links = Hash.new { |hash, key| hash[key] = [] }
      Array(parsed.is_a?(Hash) ? parsed["links"] : nil).each do |link|
        next unless link.is_a?(Hash)

        from = link["id"].to_i
        to = merged.fetch(link["depends_on"].to_i, link["depends_on"].to_i)
        next unless shown_ids.include?(from) && shown_ids.include?(to) && from != to
        next if links[from].include?(to) || links[from].size >= MAX_PER_FINDING
        next unless grounded?(by_id[from], by_id[to])
        next if DependencyGraph.loop?(edges.merge(links) { |_, mine, drafted| mine | drafted }, from, to)

        links[from] << to
      end
      links.to_h
    end
  end
end
