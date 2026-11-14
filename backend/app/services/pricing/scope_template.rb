# frozen_string_literal: true

module Pricing
  # The scope statement that goes with a Stage 1 fee (Doc 17 §2.4), written from
  # the quote's own figures. It is what the client reads when P24 can't be used
  # or its wording fails the checks (P24 §7), so it says everything §2.4 asks:
  # departments and participants, deep dives, what they receive, the
  # additional-participant rate, what isn't included, and that Stages 2 and 3
  # are priced separately, per item, after the report.
  #
  # Same shape as P24's client_scope_statement. Nothing internal.
  class ScopeTemplate
    def self.call(quote) = new(quote).call

    def initialize(quote)
      @quote = quote
    end

    def call
      {
        "what_is_included" => [
          "A conversation with you about the business and where you want to take it",
          "Conversations with #{members(@quote.participants_included)} of your team#{departments_phrase}",
          "#{sessions(@quote.deep_dives_included)} on specific pieces of work we agree are worth understanding properly",
          "A full Diagnostic Report showing where time and money are going, what can change, and what it is worth",
          "The report continues to update as further sessions complete during the engagement"
        ],
        "what_is_not_included" => [
          "Detailed solution designs — the second stage, priced per item after you have read the report",
          "Building or implementing anything — the third stage, priced once the designs exist"
        ],
        "participants_and_departments" => participants_and_departments,
        "deliverable" => "The Diagnostic Report, which keeps updating in your portal as further sessions complete " \
                         "during the engagement.",
        "additional_participants" => "If you would like more of your team to take part, each additional person is " \
                                     "#{Money.format(@quote.additional_participant_rate, @quote.currency)}.",
        "what_happens_next" => "You receive the report and decide which findings you would like taken further. " \
                               "Those you select are designed in detail and priced individually, and you decide " \
                               "again before anything is built.",
        "validity" => validity
      }
    end

    private

    def departments
      Array(@quote.inputs["departments"]).select { |d| d["count"].to_i.positive? }
    end

    def departments_phrase
      names = departments.map { |d| d["name"] }
      names.any? ? " across #{names.to_sentence}" : ""
    end

    def participants_and_departments
      rows = departments.map { |d| "#{d['name']}: #{people(d['count'])}" }
      "#{people(@quote.participants_included).capitalize} in total#{rows.any? ? " — #{rows.join('; ')}" : ''}."
    end

    def validity
      days = @quote.rate_card_version.stage1["validity_days"]
      return "This proposal stands until #{@quote.valid_until.strftime('%-d %B %Y')}." if @quote.valid_until

      "This proposal stands for #{days} days from when it is sent to you."
    end

    def people(count) = count.to_i == 1 ? "one person" : "#{count} people"
    def members(count) = count.to_i == 1 ? "one member" : "#{count} members"
    def sessions(count) = count.to_i == 1 ? "One detailed session" : "#{count} detailed sessions"
  end
end
