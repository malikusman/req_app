# frozen_string_literal: true

module Reports
  # A variant is a SECTION ALLOWLIST, a page template and a paper size — never a
  # second analysis. Both variants render from the same `report_snapshot` and the
  # same consultant overlay, so the two documents cannot disagree about a number.
  #
  # Adding a variant means adding an entry here. It needs no migration and no
  # change to the generate services.
  class VariantSpec
    FULL = "full"
    EXEC_BRIEF = "exec_brief"
    VARIANTS = [FULL, EXEC_BRIEF].freeze

    # Gotenberg wants inches. A4 landscape for the reading-room document, A4
    # portrait for the brief — an owner reads that one on a phone and forwards it.
    LANDSCAPE = { width: "11.69", height: "8.27" }.freeze
    PORTRAIT  = { width: "8.27",  height: "11.69" }.freeze

    SPECS = {
      FULL => {
        variant: FULL,
        label: "Full report",
        template: "reports/document",
        paper: LANDSCAPE,
        orientation: "landscape",
        # nil = every section. The full report is the complete record.
        sections: nil,
        description: "Every section, all evidence, the expert appendix."
      },
      EXEC_BRIEF => {
        variant: EXEC_BRIEF,
        label: "Executive brief",
        template: "reports/brief/document",
        paper: PORTRAIT,
        orientation: "portrait",
        # The answer, what it costs, what to do, who validated it. No excerpts,
        # no readiness score, no participation funnel, no methodology page.
        sections: %w[
          expert_verdict key_metrics signals patterns
          recommendations roadmap validation
        ].freeze,
        description: "The answer, the value, the first three actions, and who signed off."
      }
    }.freeze

    def self.for(variant)
      SPECS.fetch(variant.to_s) { raise ArgumentError, "Unknown report variant: #{variant.inspect}" }
    end

    def self.all
      VARIANTS.map { |v| self.for(v) }
    end

    # The brief deliberately drops sections; the full report deliberately keeps
    # them. A nil allowlist means "everything".
    def self.includes_section?(variant, key)
      allowed = self.for(variant)[:sections]
      allowed.nil? || allowed.include?(key.to_s)
    end
  end
end
