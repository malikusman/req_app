# frozen_string_literal: true

# Makes the issued quote's PDF (Pricing::QuotePdf). The portal shows the quote
# without it; the download makes it on demand if this hasn't run yet.
class QuotePdfJob < ApplicationJob
  queue_as :default

  def perform(quote_id)
    quote = Quote.find_by(id: quote_id)
    Pricing::QuotePdf.call(quote) if quote && quote.pdf_storage_key.blank?
  end
end
