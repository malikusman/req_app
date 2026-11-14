# frozen_string_literal: true

module Pricing
  # Past Stage 1 work of a similar size, for the administrator to weigh a fee
  # against (Doc 17 §9.1, §13.3). Accepted quotes of other engagements whose
  # participant count is within half of this one's either way, newest first.
  #
  # Doc 17 wants their *actual* effort beside them; consultant hours aren't
  # recorded yet, so each says so rather than implying the estimate was right.
  # No company is named: the pricing context sees sizes and fees, not clients.
  class Comparables
    LIMIT = 5

    def self.for(engagement, participants)
      return [] unless participants.to_i.positive?

      low = (participants * 0.5).floor
      high = (participants * 1.5).ceil
      Quote.stage1.where(status: "ACCEPTED", participants_included: low..high)
           .where.not(engagement_id: engagement.id)
           .order(accepted_at: :desc).limit(LIMIT)
           .map do |quote|
             { "participants" => quote.participants_included, "deep_dives" => quote.deep_dives_included,
               "fee" => quote.subtotal.to_s("F"), "currency" => quote.currency,
               "estimated_hours" => quote.internal["total_hours"], "actual_hours" => nil,
               "accepted_on" => quote.accepted_at&.to_date&.iso8601 }
           end
    end
  end
end
