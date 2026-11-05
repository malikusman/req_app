# frozen_string_literal: true

module KeyPerson
  # Stands in for the model in the conversations with leadership, outside
  # production only (KeyPerson.client_for), so the demo and the browser tests
  # run the real flow — planner, guard, validation, storage — without one.
  #
  # It is deliberately plain: P02 says the intent library's own question for
  # the area; P03 reads the answer with a few patterns (documents, people,
  # planned systems, a question, a wish to pause); P04 lays the captured
  # statements out by area. Release decisions are never made on it.
  class ScriptedClient
    MODEL = "scripted"

    def initialize
      raise "Scripted replies are for development and tests only" if Rails.env.production?
    end

    def configured? = true

    def parse_reply(content) = JSON.parse(content)

    def key_person_turn(system:, context:)
      _ = system
      result(say(context))
    end

    def key_person_capture(system:, context:)
      _ = system
      result(capture(context).to_json)
    end

    def key_person_context(system:, context:)
      _ = system
      result(management_context(context).to_json)
    end

    private

    def result(content)
      Openai::Client::ChatResult.new(content: content, model: MODEL, finish_reason: "stop", input_tokens: 0,
                                     output_tokens: 0, latency_ms: 0, escalated: false)
    end

    def say(context)
      mode = context[/^Mode: (\w+)/, 1]
      area = context[/^Target: (\w+)/, 1]
      lang = context.include?("in Modern Standard Arabic") ? "ar" : "en"
      case mode
      when "FOLLOW_UP" then lang == "ar" ? "هل يمكنك أن توضح ما تقصده قليلاً؟" : "Could you say a little more about what you mean?"
      when "EXAMPLE" then lang == "ar" ? "هل لديك مثال حديث على ذلك؟" : "Is there a recent example that comes to mind?"
      when "PRIORITY_READ_BACK"
        themes = context.scan(/^- (.+)$/).flatten
        "So far I've heard: #{themes.first(2).join(' ')} Which of these matters most to you?"
      when "DOCUMENT_REQUEST"
        documents = context[/^Documents:\n((?:- .+\n?)+)/, 1].to_s.scan(/^- (.+)$/).flatten
        "You mentioned #{documents.to_sentence}. Could you share them? It's optional, and you can add them later."
      when "HANDLE_ASIDE"
        [Intents.line("HANDLE_ASIDE", lang), area && Intents.question(area, lang)].compact.join(" ")
      when "RESUME", "QUESTION", "REFLECT_AND_ASK"
        prefix = mode == "RESUME" ? "#{Intents.line('RESUME', lang)} " : ""
        area ? "#{prefix}#{Intents.question(area, lang)}" : Intents.line("ANYTHING_ELSE", lang)
      when "CLARIFY" then area ? Intents.question(area, lang) : Intents.line("CLARIFY", lang)
      else Intents.line(mode, lang)
      end
    end

    def capture(context)
      area = context[/^target: (\w+) —/, 1]
      turn = context[/turn_id="(t\d+)"/, 1]
      answer = context[%r{<participant_answer[^>]*>\n(.*)\n</participant_answer>}m, 1].to_s.strip
      words = answer.split.size
      question = answer.end_with?("?", "؟")
      pause = answer.match?(/\b(pause|later|another time|got to go)\b/i)
      vague = words < 5 && !question && !pause

      {
        "turn_id" => turn,
        "previous_target_result" => { "domain" => area, "quality" => area && !vague && !question ? "USABLE" : (vague ? "VAGUE" : "NONE") },
        "domains_touched" => area && !vague && !question ? [{ "domain" => area, "contribution" => "USABLE" }] : [],
        "statements" => area && !vague && !question ? [statement(area, answer, turn)] : [],
        "planned_initiatives" => initiatives(answer, turn),
        "participants_mentioned" => people(answer, turn),
        "documents_mentioned" => documents(answer, turn),
        "profile_facts_discovered" => [],
        "numbers_mentioned" => [],
        "sensitive" => [],
        "political_signals" => [],
        "posture_signals" => [],
        "participant_question" => { "asked" => question, "topic" => answer.match?(/cost|price|fee/i) ? "PRICE" : "OTHER",
                                    "text" => question ? answer : nil },
        "participant_signal" => pause ? "WANTS_PAUSE" : "NONE",
        "detail_overflow" => false,
        "summary_update" => vague || question || pause ? nil : answer.truncate(140)
      }
    end

    def statement(area, answer, turn)
      { "domain" => area, "statement" => answer.truncate(240), "original_wording" => answer.truncate(80),
        "subject_area" => nil, "is_symptom_or_cause" => "NEITHER",
        "importance_signal" => answer.match?(/\b(biggest|most|really|always)\b/i) ? "EMPHASISED" : "MENTIONED",
        "fact_status" => "REPORTED", "evidence" => turn }
    end

    def documents(answer, turn)
      answer.scan(/\b((?:weekly|monthly|daily|sales|kpi|management|finance|org(?:anisation)?)\s+(?:[a-z]+\s+)?(?:pack|report|sheet|chart|policy))\b/i)
            .flatten.uniq.map { |d| { "description" => d.downcase, "evidence" => turn } }
    end

    def people(answer, turn)
      answer.scan(/\b([A-Z][a-z]+) in ([a-z]+) (?:knows|runs)/).map do |name, department|
        { "name" => name, "role" => nil, "department" => department.capitalize,
          "reason" => "Knows the day-to-day work", "evidence" => turn }
      end
    end

    def initiatives(answer, turn)
      type = answer[/\bnew (ERP|CRM)\b/i, 1]&.upcase || (answer.match?(/restructur/i) ? "RESTRUCTURE" : nil)
      return [] unless type

      [{ "type" => type, "description" => answer.truncate(160), "timing" => answer[/\b(next year|this year|in \w+)\b/i, 1],
         "affected_areas" => [], "evidence" => turn }]
    end

    FINDING_AREAS = { "CONCERNS" => "MANAGEMENT", "BOTTLENECKS" => "PROCESS", "DECISIONS_APPROVALS" => "GOVERNANCE",
                      "REPORTING" => "REPORTING", "SYSTEMS" => "SYSTEM", "GROWTH_PRIORITIES" => "GROWTH" }.freeze

    def management_context(context)
      captures = JSON.parse(context[%r{<turn_captures[^>]*>\n(.*)\n</turn_captures>}m, 1] || "[]")
      statements = captures.flat_map { |c| Array(c["statements"]) }
      fields = ContextValidator::LIST_FIELDS.index_with { [] }
      statements.each do |s|
        field = ContextBuilder::AREA_FIELDS[s["domain"]]
        next unless field

        fields[field] << if field == "released_time_preferences"
                           { "role_or_team" => "Team", "preferred_focus" => s["statement"], "evidence" => [s["evidence"]] }
                         else
                           { "text" => s["statement"], "evidence" => [s["evidence"]] }
                         end
      end
      success = statements.find { |s| s["domain"] == "SUCCESS_DEFINITION" }
      {
        "management_context" => fields.merge(
          "success_definition" => { "text" => success&.dig("statement"), "evidence" => [success&.dig("evidence")].compact },
          "change_appetite_inferred" => { "level" => "UNCLEAR", "basis" => "Scripted run", "fact_status" => "INFERRED" }
        ),
        "strategic_findings" => statements.filter_map do |s|
          next unless FINDING_AREAS.key?(s["domain"])

          { "category" => FINDING_AREAS[s["domain"]], "scope" => "COMPANY", "statement" => s["statement"],
            "symptom_or_cause" => "SYMPTOM", "source_basis" => "MANAGEMENT_STATEMENT", "fact_status" => "REPORTED",
            "management_importance" => s["importance_signal"] == "EMPHASISED" ? "HIGH" : "MEDIUM",
            "validation_need" => "Check with the people who do this work how it runs day to day.",
            "evidence" => [s["evidence"]] }
        end,
        "planned_initiatives" => captures.flat_map { |c| Array(c["planned_initiatives"]) }.map do |i|
          i.merge("status" => "PROPOSED", "evidence" => [i["evidence"]])
        end,
        "neutral_context_for_employee_discovery" => [
          { "department" => "Company", "context" => "The company is looking at where everyday work could run more smoothly." }
        ],
        "political_context" => {}, "unknowns" => [], "contradictions" => [], "consultant_notes" => [],
        "completion" => { "domains_adequate" => statements.pluck("domain").uniq, "domains_thin" => [], "confidence" => "MEDIUM" }
      }
    end
  end
end
