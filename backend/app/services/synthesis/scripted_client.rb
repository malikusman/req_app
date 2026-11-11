# frozen_string_literal: true

module Synthesis
  # Stands in for the model in synthesis, outside production only
  # (Synthesis.client_for), so the demo and the browser tests run the real flow
  # — candidates, validation, clustering, effort arithmetic, storage, review —
  # without one.
  #
  # Deliberately plain. P10 reads the shortlisting signals: the same person
  # giving the same figures is one execution; the same department and the same
  # kind of work is one process done by each person; the same kind of work
  # across departments is a handoff; anything else is kept apart. Release
  # decisions are never made on it.
  class ScriptedClient
    MODEL = "scripted"

    def initialize
      raise "Scripted replies are for development and tests only" if Rails.env.production?
    end

    def configured? = true

    def parse_reply(content) = JSON.parse(content)

    def process_relationship(system:, context:)
      _ = system
      result(relationship(context).to_json)
    end

    # P11 from the context blocks alone: one opportunity per cluster, quoting
    # its figure; each leadership finding supported where staff work shares its
    # words, otherwise not yet observed; a root cause only where two pieces of
    # work share a system.
    def synthesis(system:, context:)
      _ = system
      result(synthesis_reply(context).to_json)
    end

    private

    def synthesis_reply(context)
      clusters = block(context, "process_clusters") || []
      figures = (block(context, "effort_normalisation") || []).to_h { |f| [f["cluster"], f["figure"]] }
      work = block(context, "work_items") || []
      leadership = block(context, "management_contexts") || []
      coverage = block(context, "coverage") || {}
      units = clusters.map { |c| { "ref" => c["ref"], "words" => words("#{c['name']} #{c['members'].map { |m| m['title'] }.join(' ')}") } } +
              work.map { |w| { "ref" => w["ref"], "words" => words("#{w['title']} #{w['what_happens_now']} #{w['what_snags']}") } }
      findings = leadership.flat_map { |l| Array(l["strategic_findings"]) }

      {
        "operating_picture" => operating_picture(clusters, work),
        "root_causes" => root_causes(clusters, work),
        "opportunities" => clusters.map { |c| opportunity(c, figures[c["ref"]], findings) },
        "management_versus_evidence" => findings.map { |sf| leadership_verdict(sf, units) },
        "initiative_conflicts" => [],
        "role_potential_summary" => Array(block(context, "role_potential")).filter_map do |r|
          role = r["role"] || r["role_or_team"]
          focus = r["notes"] || [r["preferred_focus"]].compact
          { "role" => role, "department" => r["department"], "potential_focus" => focus,
            "basis" => r["source"] == "MANAGEMENT" ? "MANAGEMENT" : "PARTICIPANT", "evidence" => [] } if role && focus.any?
        end,
        "coverage_notes" => Array(coverage["departments_planned_not_covered"]).map do |d|
          { "note" => "#{d} has not been covered yet, so nothing here describes it." }
        end,
        "confidence" => clusters.any? ? "MEDIUM" : "LOW"
      }
    end

    def operating_picture(clusters, work)
      departments = (work.map { |w| w["department"] } + clusters.flat_map { |c| c["departments"] }).compact.uniq
      {
        "how_the_business_runs" => "Work described so far sits in #{departments.to_sentence.presence || 'one area'}.",
        "departments" => departments.map do |d|
          titles = work.select { |w| w["department"] == d }.map { |w| w["title"] }.first(3)
          { "name" => d, "what_it_does" => titles.any? ? "Staff describe #{titles.to_sentence.downcase}." : "Shares work with other teams.",
            "main_systems" => [] }
        end,
        "work_flows_between" => [], "where_information_lives" => [], "ai_and_automation_in_use" => [],
        "evidence" => (clusters.map { |c| c["ref"] } + work.map { |w| w["ref"] }).first(5)
      }
    end

    def root_causes(clusters, work)
      by_system = (clusters + work).flat_map { |u| Array(u["systems"]).map { |s| [s, u["ref"]] } }.group_by(&:first)
      by_system.select { |_, rows| rows.size >= 2 }.map do |system, rows|
        refs = rows.map(&:last).uniq
        { "statement" => "The same information is handled by hand around #{system} in several places.",
          "explains" => refs, "affected_departments" => [], "supporting_signals" => ["Several pieces of work rely on #{system}"],
          "fact_status" => "INFERRED", "confidence" => "MEDIUM",
          "what_would_confirm_it" => "Check in a deep dive how #{system} is fed and read.", "evidence" => refs }
      end
    end

    def opportunity(cluster, figure, findings)
      departments = Array(cluster["departments"])
      linked = findings.select { |sf| overlap(words(sf["statement"]), words(cluster["name"])) >= 0.15 }
      {
        "title" => "One way of handling #{cluster['name'].to_s.downcase}",
        "level" => departments.size > 1 ? "CROSS_DEPARTMENT" : (cluster["type"] == "END_TO_END" ? "PROCESS" : "SHARED_TASK"),
        "category" => "PROCESS",
        "problem_statement" => "Several people handle #{cluster['name'].to_s.downcase} separately, so the same effort is repeated.",
        "evidence_summary" => "Grouped from what staff described.",
        "affected_clusters" => [cluster["ref"]], "affected_departments" => departments, "root_cause_ref" => nil,
        "capacity_reference" => figure, "other_value" => ["QUALITY"],
        "intervention_direction" => "Agree one shared way of doing this work and support it with a common tool.",
        "ai_relevance" => "SUPPORTING", "ai_note" => "AI could help prepare the routine parts; to be verified.",
        "management_alignment" => linked.first&.dig("statement"), "planned_initiative_conflict" => nil,
        "dependencies" => [], "recommended_next_action" => "DEEP_DIVE",
        "priority_reason" => "Shared by several people.", "confidence" => "MEDIUM",
        "evidence" => [cluster["ref"]] + linked.map { |sf| sf["ref"] }
      }
    end

    def leadership_verdict(finding, units)
      statement = words(finding["statement"])
      matches = units.select { |u| overlap(statement, u["words"]) >= 0.1 }.map { |u| u["ref"] }
      {
        "management_view" => finding["statement"],
        "what_evidence_shows" => matches.any? ? "Staff describe related work." : "Not raised by staff so far.",
        "relationship" => matches.any? ? "SUPPORTED" : "NOT_YET_OBSERVED",
        "note" => matches.any? ? "Staff accounts point the same way." : "Worth checking as more staff take part.",
        "evidence" => [finding["ref"]] + matches.first(3)
      }
    end

    def block(context, name)
      body = context[%r{<#{name} trust="platform">\n(.*?)\n</#{name}>}m, 1]
      body && JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def words(text) = Findings::Words.of(text)
    def overlap(one, other) = Findings::Words.overlap(one, other)

    def result(content)
      Openai::Client::ChatResult.new(content: content, model: MODEL, finish_reason: "stop", input_tokens: 0,
                                     output_tokens: 0, latency_ms: 0, escalated: false)
    end

    def relationship(context)
      signals = context[%r{<shared_signals trust="platform">\n(.*?)\n</shared_signals>}m, 1].to_s
      same_person = signals.include?("same person gave the same figures")
      same_work = signals.match?(/same kind of work|Overlapping description/)
      same_department = signals.include?("Same department")

      if same_person
        verdict("SAME_PROCESS", "HIGH", "AUTO_CLUSTER", "YES", "One person described the same work twice.")
      elsif same_work && same_department
        verdict("SAME_PROCESS", "MEDIUM", "PROVISIONAL_CLUSTER", "NO",
                "Both describe the same kind of work in one department; each does their own share.")
      elsif same_work
        verdict("PROCESS_STAGE", "MEDIUM", "PROVISIONAL_CLUSTER", "NO",
                "The same work passes between departments; each handles their own stage.")
      else
        verdict("INDEPENDENT", "LOW", "KEEP_SEPARATE", "UNKNOWN", "Too little in common to group.")
      end
    end

    def verdict(type, confidence, recommendation, same_execution, rationale)
      {
        "relationship" => type, "confidence" => confidence, "recommendation" => recommendation,
        "evidence_for" => type == "INDEPENDENT" ? [] : ["Shortlisting signals agree"], "evidence_against" => [],
        "tests" => { "same_purpose" => type == "INDEPENDENT" ? "UNKNOWN" : "YES" },
        "variant_assessment" => { "material_differences" => [], "would_one_deep_dive_represent_both" => "UNSURE",
                                  "distinguishing_factors" => ["NONE"] },
        "clarification_needed" => nil,
        "effort_overlap" => { "same_execution" => same_execution, "note" => rationale },
        "rationale" => rationale
      }
    end
  end
end
