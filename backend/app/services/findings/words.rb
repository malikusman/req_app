# frozen_string_literal: true

module Findings
  # The words that say which work a finding is about, for comparing findings by
  # rule: two findings for the same work (Reports::Critic), or a link whose reason
  # names the work it points at (Findings::DraftDependencies).
  module Words
    # Words that say nothing about which work: grammar, and what every finding
    # shares — manual work, data, records, systems.
    STOPWORDS = %w[a an and the of to for in on with by from at is are be it its this that as or into than
                   their they them each every all any one more less before after so can need needs must kept
                   manual manually work process data record system format information time task consistent
                   consistently clear reliable structured single digital].to_set.freeze

    module_function

    # Lowercase content words, crudely singular ("orders" → "order").
    def of(text, ignore: [])
      skip = STOPWORDS | ignore.map(&:downcase)
      text.to_s.downcase.scan(/[a-z]+/).reject { |w| w.length < 3 || skip.include?(w) }
          .map { |w| w.length > 3 ? w.sub(/s\z/, "") : w }.to_set
    end

    # Jaccard overlap of two word sets, 0.0 when either is empty.
    def overlap(one, other)
      return 0.0 if one.empty? || other.empty?

      (one & other).size.to_f / (one | other).size
    end
  end
end
