# frozen_string_literal: true

module Synthesis
  # Checks P11's reply before anything is stored (P11 §10). An item that fails
  # a hard rule is dropped; a field that fails a soft one is emptied. Nothing is
  # repaired by guessing, and every drop is recorded with why, so the consultant
  # and the eval can see what the model was overruled on.
  #
  # Hard, per item:
  #   - unknown level, category, next action, confidence or relationship;
  #   - no reference to anything that exists — every root cause and opportunity
  #     must cite real objects; a root cause must explain at least two;
  #   - its problem or statement names a person, describes one, or carries a
  #     figure the platform never computed.
  # Soft, per field:
  #   - a capacity_reference that isn't one of the platform's figures, quoted
  #     exactly;
  #   - an intervention direction that reads as a design (trigger, endpoint,
  #     API, field mapping, prompt, schema) or runs past its length cap;
  #   - any other text that names someone or carries an ungrounded figure.
  # Root causes are always INFERRED, whatever the model said.
  class SynthesisValidator
    class Invalid < StandardError; end

    DIRECTION_MAX = 300
    TEXT_MAX = 1200
    DESIGN = /\b(trigger|endpoint|api|apis|field[- ]mapping|mapping rules?|prompt|schema|webhook|json)\b/i
    # Describes a person rather than the work (P11 §8.3, Doc 00 C15): "he" or
    # "she", or a role held up as the problem — "the procurement officer is
    # slow". "Approvals are slow" is about work and passes.
    ABOUT_A_PERSON = /\b(?:he|she)\b|
                      \b(?:officer|clerk|manager|coordinator|accountant|assistant|employee|person|buyer|salesperson|
                         analyst|supervisor|lead)\s+(?:\w+\s+){0,2}(?:is|was)\s+(?:too\s+|very\s+)?
                      (?:slow|lazy|careless|incompetent|unreliable|disorganised|disorganized|weak|bad\s+at|poor\s+at)\b/xi
    RELATIONSHIPS = ManagementValidation::RELATIONSHIPS
    EFFECTS = %w[REMOVES REPLACES PARTIALLY_AFFECTS UNCERTAIN].freeze
    CONFLICT_ADVICE = %w[DEFER INTERIM_ONLY PROCEED CLARIFY].freeze
    BASIS = %w[PARTICIPANT MANAGEMENT BOTH].freeze
    CONFIDENCE = %w[HIGH MEDIUM LOW].freeze

    attr_reader :drops

    def initialize(raw, pack:)
      @raw = raw
      @pack = pack
      @drops = []
    end

    def call
      raise Invalid, "reply is not an object" unless @raw.is_a?(Hash)

      root_causes = Array(@raw["root_causes"]).each_with_index.filter_map { |rc, i| root_cause(rc, i) }
      {
        "operating_picture" => operating_picture(@raw["operating_picture"]),
        "root_causes" => root_causes,
        "opportunities" => Array(@raw["opportunities"]).each_with_index.filter_map { |op, i| opportunity(op, i, root_causes) },
        "validations" => Array(@raw["management_versus_evidence"]).each_with_index.filter_map { |v, i| validation(v, i) },
        "initiative_conflicts" => Array(@raw["initiative_conflicts"]).each_with_index.filter_map { |c, i| conflict(c, i) },
        "role_potential" => Array(@raw["role_potential_summary"]).each_with_index.filter_map { |r, i| role_potential(r, i) },
        "coverage_notes" => Array(@raw["coverage_notes"]).filter_map { |n| text(n.is_a?(Hash) ? n["note"] : n, "coverage_notes") }
                                                        .map { |n| { "note" => n } },
        "confidence" => CONFIDENCE.include?(@raw["confidence"]) ? @raw["confidence"] : "LOW"
      }
    end

    private

    def operating_picture(raw)
      return {} unless raw.is_a?(Hash)

      {
        "how_the_business_runs" => text(raw["how_the_business_runs"], "operating_picture.how_the_business_runs"),
        "departments" => Array(raw["departments"]).filter_map do |d|
          next unless d.is_a?(Hash) && (name = text(d["name"], "operating_picture.departments.name"))

          { "name" => name, "what_it_does" => text(d["what_it_does"], "operating_picture.departments.what_it_does"),
            "main_systems" => strings(d["main_systems"], "operating_picture.departments.main_systems") }.compact
        end,
        "work_flows_between" => Array(raw["work_flows_between"]).filter_map do |f|
          next unless f.is_a?(Hash)

          flow = %w[from to what_moves how].to_h { |k| [k, text(f[k], "operating_picture.work_flows_between.#{k}")] }
          flow if flow["from"] && flow["to"] && flow["what_moves"]
        end,
        "where_information_lives" => strings(raw["where_information_lives"], "operating_picture.where_information_lives"),
        "ai_and_automation_in_use" => strings(raw["ai_and_automation_in_use"], "operating_picture.ai_and_automation_in_use"),
        "evidence" => refs(raw["evidence"], "operating_picture")
      }.compact
    end

    def root_cause(raw, index)
      where = "root_causes[#{index}]"
      return drop(where, "not an object") unless raw.is_a?(Hash)
      return drop(where, "confidence #{raw['confidence'].inspect}") unless CONFIDENCE.include?(raw["confidence"])

      statement = text(raw["statement"], "#{where}.statement", hard: true)
      return drop(where, "statement unusable") unless statement

      explains = refs(raw["explains"], where)
      return drop(where, "explains fewer than two real objects") if explains.size < 2

      {
        "statement" => statement, "explains" => explains,
        "affected_departments" => strings(raw["affected_departments"], "#{where}.affected_departments"),
        "supporting_signals" => strings(raw["supporting_signals"], "#{where}.supporting_signals"),
        "fact_status" => "INFERRED", "confidence" => raw["confidence"],
        "what_would_confirm" => text(raw["what_would_confirm_it"], "#{where}.what_would_confirm_it"),
        "evidence" => (explains + refs(raw["evidence"], where)).uniq
      }
    end

    def opportunity(raw, index, root_causes)
      where = "opportunities[#{index}]"
      return drop(where, "not an object") unless raw.is_a?(Hash)

      { "level" => ConsultancyOpportunity::LEVELS, "category" => ConsultancyOpportunity::CATEGORIES,
        "recommended_next_action" => ConsultancyOpportunity::NEXT_ACTIONS, "confidence" => CONFIDENCE }.each do |field, allowed|
        return drop(where, "#{field} #{raw[field].inspect}") unless allowed.include?(raw[field])
      end
      title = text(raw["title"], "#{where}.title", hard: true)
      problem = text(raw["problem_statement"], "#{where}.problem_statement", hard: true)
      return drop(where, "title or problem unusable") unless title && problem

      affected = refs(raw["affected_clusters"], where)
      evidence = (affected + refs(raw["evidence"], where)).uniq
      return drop(where, "cites nothing that exists") if evidence.empty?

      {
        "level" => raw["level"], "category" => raw["category"], "title" => title, "problem_statement" => problem,
        "evidence_summary" => text(raw["evidence_summary"], "#{where}.evidence_summary"),
        "affected" => affected, "evidence" => evidence,
        "affected_departments" => strings(raw["affected_departments"], "#{where}.affected_departments"),
        "root_cause_index" => root_cause_index(raw["root_cause_ref"], root_causes),
        "capacity_reference" => capacity(raw["capacity_reference"], where),
        "other_value" => Array(raw["other_value"]) & ConsultancyOpportunity::OTHER_VALUES,
        "intervention_direction" => direction(raw["intervention_direction"], "#{where}.intervention_direction"),
        "ai_relevance" => ConsultancyOpportunity::AI_RELEVANCE.include?(raw["ai_relevance"]) ? raw["ai_relevance"] : nil,
        "ai_note" => direction(raw["ai_note"], "#{where}.ai_note"),
        "management_alignment" => text(raw["management_alignment"], "#{where}.management_alignment"),
        "planned_initiative_conflict" => text(raw["planned_initiative_conflict"], "#{where}.planned_initiative_conflict"),
        "dependencies" => strings(raw["dependencies"], "#{where}.dependencies"),
        "recommended_next_action" => raw["recommended_next_action"],
        "priority_reason" => text(raw["priority_reason"], "#{where}.priority_reason"),
        "confidence" => raw["confidence"]
      }
    end

    def validation(raw, index)
      where = "management_versus_evidence[#{index}]"
      return drop(where, "not an object") unless raw.is_a?(Hash)
      return drop(where, "relationship #{raw['relationship'].inspect}") unless RELATIONSHIPS.include?(raw["relationship"])

      view = text(raw["management_view"], "#{where}.management_view", hard: true)
      return drop(where, "management view unusable") unless view

      evidence = refs(raw["evidence"], where)
      finding = strategic_finding_for(evidence, view)
      return drop(where, "matches none of leadership's strategic findings") unless finding

      {
        "strategic_finding" => finding, "management_view" => view, "relationship" => raw["relationship"],
        "what_evidence_shows" => text(raw["what_evidence_shows"], "#{where}.what_evidence_shows"),
        "note" => text(raw["note"], "#{where}.note"), "evidence" => evidence
      }
    end

    def conflict(raw, index)
      where = "initiative_conflicts[#{index}]"
      return drop(where, "not an object") unless raw.is_a?(Hash)

      initiative = text(raw["initiative"], "#{where}.initiative", hard: true)
      affected = refs(raw["affected"], where)
      return drop(where, "names no initiative or nothing it affects") unless initiative && affected.any?

      { "initiative" => initiative, "affected" => affected,
        "effect" => EFFECTS.include?(raw["effect"]) ? raw["effect"] : "UNCERTAIN",
        "recommendation" => CONFLICT_ADVICE.include?(raw["recommendation"]) ? raw["recommendation"] : "CLARIFY" }
    end

    def role_potential(raw, index)
      where = "role_potential_summary[#{index}]"
      return drop(where, "not an object") unless raw.is_a?(Hash)

      role = text(raw["role"], "#{where}.role", hard: true)
      focus = strings(raw["potential_focus"], "#{where}.potential_focus")
      return drop(where, "no role or focus") unless role && focus.any?

      { "role" => role, "department" => text(raw["department"], "#{where}.department"), "potential_focus" => focus,
        "basis" => BASIS.include?(raw["basis"]) ? raw["basis"] : "PARTICIPANT",
        "evidence" => refs(raw["evidence"], where) }.compact
    end

    # Leadership's finding a verdict is about: one it cites, or failing that the
    # one whose statement it restates.
    def strategic_finding_for(evidence, view)
      cited = evidence.select { |e| e["type"] == "strategic_finding" }.map { |e| e["id"] }
      by_id = @pack.strategic_findings.index_by(&:id)
      return by_id[cited.first] if cited.any? && by_id[cited.first]

      words = Findings::Words.of(view)
      best = @pack.strategic_findings.max_by { |sf| Findings::Words.overlap(words, Findings::Words.of(sf.statement)) }
      best if best && Findings::Words.overlap(words, Findings::Words.of(best.statement)) >= 0.3
    end

    def root_cause_index(ref, root_causes)
      return nil if ref.blank? || root_causes.empty?

      words = Findings::Words.of(ref)
      scored = root_causes.each_with_index.map do |rc, i|
        [i, Findings::Words.overlap(words, Findings::Words.of(rc["statement"]))]
      end
      index, score = scored.max_by(&:last)
      score >= 0.3 ? index : nil
    end

    def capacity(value, where)
      value = value.to_s.strip
      return nil if value.empty?

      figure = @pack.figure_matching(value)
      return figure.text if figure

      drop("#{where}.capacity_reference", "not a platform figure quoted exactly: #{value.truncate(80)}")
      nil
    end

    def direction(value, field)
      value = text(value, field)
      return nil unless value

      if value.match?(DESIGN)
        drop(field, "reads as a design")
        return nil
      end
      return value if value.length <= DIRECTION_MAX

      cut = value[0, DIRECTION_MAX][/\A.*[.!?](?=\s|\z)/m]
      drop(field, "longer than #{DIRECTION_MAX} characters#{cut ? '; cut to whole sentences' : ''}")
      cut
    end

    def refs(value, where)
      Array(value).filter_map do |ref|
        resolved = @pack.resolve(ref)
        drop(where, "cites #{ref.to_s.truncate(40).inspect}, which does not exist") unless resolved
        resolved
      end.uniq
    end

    def strings(value, field) = Array(value).filter_map { |s| text(s, field) }

    def text(value, field, hard: false)
      return nil unless value.is_a?(String) || value.is_a?(Numeric)

      value = value.to_s.strip
      return nil if value.empty?

      problem = if @pack.names_someone?(value) then "names a person"
                elsif value.match?(ABOUT_A_PERSON) then "describes a person"
                elsif !Llm::GroundedNumbers.grounded?(value, @pack.allowed_numbers)
                  # The figure alone, never the text: the text may name someone.
                  stray = (Llm::GroundedNumbers.figures(value) - @pack.allowed_numbers.to_set).first(3).join(", ")
                  "carries a figure the platform never computed (#{stray})"
                elsif value.length > TEXT_MAX then "too long"
                end
      return value unless problem

      drop(field, "#{hard ? '' : 'field '}#{problem}")
      nil
    end

    def drop(where, note)
      @drops << { "stage" => "P11", "where" => where, "note" => note }
      nil
    end
  end
end
