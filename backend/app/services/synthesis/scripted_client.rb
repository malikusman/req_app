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

    private

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
