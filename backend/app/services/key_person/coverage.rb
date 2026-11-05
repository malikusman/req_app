# frozen_string_literal: true

module KeyPerson
  # The sixteen areas the conversation covers: Doc 08 §8's fourteen domains plus
  # ambition and released time (§8.1), and how much each matters for each kind of
  # person (§8.2). Coverage lives in structured state, never only in prompt prose
  # (§33): the platform tracks it, the participant never sees a checklist.
  module Coverage
    AREAS = %w[STRATEGIC_OBJECTIVES GROWTH_PRIORITIES CONCERNS BOTTLENECKS STAKEHOLDER_EXPERIENCE PEOPLE_WORKLOAD
               SYSTEMS REPORTING DECISIONS_APPROVALS DATA_DOCUMENTS PLANNED_INITIATIVES CONSTRAINTS SUCCESS_DEFINITION
               PRIORITY_AREAS AMBITION RELEASED_TIME].freeze

    ESSENTIAL = 3
    IMPORTANT = 2
    WHERE_RELEVANT = 1

    # Doc 08 §8.2: [CEO / owner, GM / COO, department head]. The table's
    # qualitative cells ("Strategic direction", "Department KPIs") are the same
    # area seen from a different height, weighted Important.
    WEIGHTS = {
      "STRATEGIC_OBJECTIVES" => [ESSENTIAL, ESSENTIAL, ESSENTIAL],
      "GROWTH_PRIORITIES" => [ESSENTIAL, IMPORTANT, WHERE_RELEVANT],
      "CONCERNS" => [ESSENTIAL, ESSENTIAL, ESSENTIAL],
      "BOTTLENECKS" => [IMPORTANT, ESSENTIAL, ESSENTIAL],
      "STAKEHOLDER_EXPERIENCE" => [IMPORTANT, IMPORTANT, IMPORTANT],
      "PEOPLE_WORKLOAD" => [IMPORTANT, ESSENTIAL, ESSENTIAL],
      "SYSTEMS" => [IMPORTANT, IMPORTANT, IMPORTANT],
      "REPORTING" => [IMPORTANT, IMPORTANT, IMPORTANT],
      "DECISIONS_APPROVALS" => [IMPORTANT, ESSENTIAL, ESSENTIAL],
      "DATA_DOCUMENTS" => [WHERE_RELEVANT, IMPORTANT, IMPORTANT],
      "PLANNED_INITIATIVES" => [ESSENTIAL, ESSENTIAL, ESSENTIAL],
      "CONSTRAINTS" => [ESSENTIAL, IMPORTANT, IMPORTANT],
      "SUCCESS_DEFINITION" => [ESSENTIAL, ESSENTIAL, ESSENTIAL],
      "PRIORITY_AREAS" => [ESSENTIAL, ESSENTIAL, ESSENTIAL],
      "AMBITION" => [ESSENTIAL, IMPORTANT, IMPORTANT],
      "RELEASED_TIME" => [IMPORTANT, IMPORTANT, ESSENTIAL]
    }.freeze

    COLUMNS = { ceo: 0, gm: 1, department_head: 2 }.freeze

    # OPEN: not yet heard. PARTIAL: touched, not enough to record usefully.
    # USABLE: enough. UNKNOWN: asked and followed up without a usable answer, so
    # it is kept as an unknown rather than asked again (Doc 08 §22, §33).
    STATUSES = %w[OPEN PARTIAL USABLE UNKNOWN].freeze
    RESOLVED = %w[USABLE UNKNOWN].freeze

    module_function

    def weight(area, persona)
      WEIGHTS.fetch(area).fetch(COLUMNS.fetch(Personas.column(persona)))
    end

    def blank_state
      AREAS.index_with do
        { "status" => "OPEN", "asked" => 0, "follow_up_used" => false, "overflow" => false, "emphasised" => false }
      end
    end

    # Sufficient when every Essential area is resolved and every Important one has
    # at least been raised (Doc 08 §22: "reasonably understood", "at least broadly
    # captured", "known or explicitly unknown"). Where-relevant areas never hold
    # the conversation open.
    def sufficient?(coverage, persona)
      AREAS.all? do |area|
        entry = coverage.fetch(area)
        case weight(area, persona)
        when ESSENTIAL then resolved?(entry)
        when IMPORTANT then entry["status"] != "OPEN" || entry["asked"].positive?
        else true
        end
      end
    end

    # Settled: usable, kept as unknown, or as much as this conversation should
    # ask — followed up once, or gone into operational detail (§9.1A).
    def resolved?(entry) = entry["settled"] == true || RESOLVED.include?(entry["status"])
  end
end
