# frozen_string_literal: true

module Pricing
  # Stands in for the model in demos and tests: writes a P24 reply from the
  # context's own figures, quoting each amount exactly as given, so the checks
  # pass the way a good reply would.
  class ScriptedClient
    MODEL = "scripted-p24"

    def configured? = true

    def stage1_price_explanation(system:, context:)
      _ = system
      result(reply(context).to_json)
    end

    def parse_reply(content) = JSON.parse(content)

    private

    def reply(context)
      fees = block(context, "fee_components")
      people = block(context, "participants")
      hours = block(context, "expected_consultant_hours")
      margin = block(context, "margin")
      risks = block(context, "risk_signals")
      rate = block(context, "additional_participant_rate")
      sessions = block(context, "deep_dives_expected")
      departments = people["by_department"].keys
      {
        "administrator_view" => {
          "headline" => "#{fees['subtotal']} before tax — driven mainly by #{people['total']} participants " \
                        "across #{departments.size} departments and #{sessions} deep dives.",
          "derivation" => fees["lines"].map { |l| { "component" => l["component"], "amount" => l["amount"], "why" => l["covers"] } },
          "effort_basis" => "About #{hours['total']} consultant hours, most of it oversight, report review and the deep dives.",
          "comparables_note" => block(context, "comparables").empty? ? "No comparable engagements yet." : "Comparable engagements are listed below.",
          "margin_note" => "#{margin['margin_percent']}% against fully loaded cost; the floor is #{margin['floor_percent']}%.",
          "confidence" => risks.size >= 3 ? "LOW" : "MEDIUM",
          "what_could_make_this_wrong" => risks,
          "recommendation_note" => "Nothing further to weigh."
        },
        "client_scope_statement" => {
          "what_is_included" => [
            "A conversation with you about the business and where you want to take it",
            "Conversations with #{people['total']} of your team across #{departments.to_sentence}",
            "#{sessions} detailed sessions on the specific pieces of work we agree are worth understanding properly",
            "A full diagnostic report showing where time and money are going, what can change, and what it is worth",
            "The report continues to update as further sessions complete during the engagement"
          ],
          "what_is_not_included" => [
            "Detailed solution designs — the second stage, priced per item after you have read the report",
            "Building or implementing anything — the third stage, priced once the designs exist"
          ],
          "participants_and_departments" => "#{people['total']} people: " +
                                            people["by_department"].map { |d, n| "#{d} #{n}" }.join(", ") + ".",
          "deliverable" => "The diagnostic report, which keeps updating in your portal during the engagement.",
          "additional_participants" => "If you would like more of your team to take part, each additional person is #{rate}.",
          "what_happens_next" => "You receive the report and choose which findings to take further; those are " \
                                 "designed and priced individually, and you decide again before anything is built.",
          "validity" => "This proposal stands for 30 days."
        }
      }
    end

    def block(context, name)
      JSON.parse(context[%r{<#{name} trust="[^"]+">\n(.*?)\n</#{name}>}m, 1])
    end

    def result(content)
      Openai::Client::ChatResult.new(content: content, model: MODEL, finish_reason: "stop", input_tokens: 0,
                                     output_tokens: 0, latency_ms: 0, escalated: false)
    end
  end
end
