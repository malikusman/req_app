# frozen_string_literal: true

# Explains a proposed Stage 1 quote with P24 (Pricing::Explainer).
class ExplainStage1QuoteJob < ApplicationJob
  queue_as :default

  def perform(quote_id)
    quote = Quote.find_by(id: quote_id)
    Pricing::Explainer.call(quote) if quote
  end
end
