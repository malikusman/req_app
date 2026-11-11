# frozen_string_literal: true

module Pricing
  # The people invited beyond what the accepted Stage 1 price covers, and what
  # they come to at the additional-participant rate agreed up front (Doc 17
  # §2.1, §12; Doc 06 §3.6). Shown to the client and to Mjadi; nothing is
  # invoiced from it yet (payment terms are open, Decision Register K1).
  #
  # Staff only: other managers added after pricing are flagged but the fee has
  # no line for them, so they aren't charged until that is decided.
  module AdditionalParticipants
    def self.for(engagement)
      quote = engagement&.accepted_stage1_quote
      return nil unless quote

      people = engagement.participants.employees.where(added_after_pricing: true).order(:created_at)
      rate = quote.additional_participant_rate
      {
        count: people.size, rate: rate.to_s("F"), currency: quote.currency,
        amount: (rate * people.size).to_s("F"),
        people: people.map { |p| { name: p.name, department: p.department, added_on: p.created_at.to_date.iso8601 } }
      }
    end
  end
end
