# frozen_string_literal: true

module Pricing
  # An issued quote not accepted by its validity date expires (Doc 06 §10.10,
  # Doc 17 §10.1). Mjadi is told; an administrator can issue a fresh version or
  # close the engagement. Run daily.
  class Expire
    def self.call(today: Time.zone.today)
      Quote.stage1.where(status: "ISSUED").where(valid_until: ...today).find_each.count do |quote|
        expired = quote.with_lock do
          next false unless quote.issued? && quote.past_validity?(today)

          quote.update!(status: "EXPIRED")
          quote.record!("expired", detail: { valid_until: quote.valid_until.iso8601 })
          true
        end
        Notifications.decided(quote) if expired
        expired
      end
    end
  end
end
