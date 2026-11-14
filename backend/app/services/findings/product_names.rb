# frozen_string_literal: true

module Findings
  # Whether model-written text names a catalogue product or vendor. Stage 1 says
  # what kind of change, never which product — that choice is Stage 2's design.
  # Shared by everything that drafts client-facing words from findings.
  module ProductNames
    # Product names are proper nouns, so they match as written. A product named
    # with an everyday word — "Make", "Notion" — counts only mid-sentence, where
    # the capital marks it as a name; "Make customer orders clear" is the verb.
    COMMON_WORD_PRODUCTS = %w[make notion monday asana basecamp].freeze

    def names_a_product?(text)
      @product_names ||= SolutionCatalogEntry.pluck(:name, :vendor).flatten.compact
                                             .map { |n| n.to_s.strip }.select { |n| n.length >= 3 }.uniq
      @product_names.any? do |name|
        pattern = /\b#{Regexp.escape(name)}\b/
        if COMMON_WORD_PRODUCTS.include?(name.downcase)
          text.to_s.split(/(?<=[.!?])\s+/).any? { |sentence| sentence.sub(/\A\s*\S+/, "").match?(pattern) }
        else
          text.to_s.match?(pattern)
        end
      end
    end
  end
end
