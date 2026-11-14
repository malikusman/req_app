# frozen_string_literal: true

# Everything that happens to a quote, in order: made, explained, adjusted,
# issued, viewed, accepted, declined, expired (Doc 17 §18). Kept as written.
class QuoteEvent < ApplicationRecord
  EVENTS = %w[proposed explained explanation_fallback issued adjusted floor_overridden inputs_changed rejected
              superseded viewed pdf_generated accepted declined expired].freeze

  belongs_to :quote
  belongs_to :actor, polymorphic: true, optional: true

  validates :event, inclusion: { in: EVENTS }

  def readonly? = persisted?
end
