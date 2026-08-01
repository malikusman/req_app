# frozen_string_literal: true

module Catalog
  # Scores how well a company's own/in-house solutions address the frictions this
  # engagement surfaced. Description-aware: matches the solution's name +
  # description + capabilities against real signal labels and pattern titles.
  # Deterministic and grounded — no fabricated fit numbers.
  class OwnedSolutionFitService
    STOPWORDS = %w[the a an and or of to for in on with our we built app application tool system platform ai agent solution service].freeze

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      solutions = @company.company_systems.active.owned_solutions.order(:name).to_a
      return [] if solutions.empty?

      signals = @company.company_signals.order(strength: :desc).to_a
      patterns = @company.patterns.order(confidence: :desc).to_a

      solutions.map { |sol| fit_for(sol, signals, patterns) }
    end

    private

    def fit_for(sol, signals, patterns)
      terms = tokenize("#{sol.name} #{sol.description} #{sol.capabilities}")

      addressed_signals = signals.select { |s| overlap?(terms, s.label) }
      addressed_patterns = patterns.select { |p| overlap?(terms, p.title) }

      # Confidence: coverage of the top frictions this solution plausibly touches,
      # capped so a broad description can't claim total coverage.
      total = [signals.size, 1].max
      coverage = addressed_signals.size.to_f / total
      confidence = [(0.35 + coverage * 0.6), 0.95].min
      confidence = 0.3 if addressed_signals.empty? && addressed_patterns.empty?

      {
        "id" => sol.id,
        "name" => sol.name,
        "category" => sol.category,
        "description" => sol.description.to_s.truncate(400),
        "capabilities" => sol.capabilities.to_s.truncate(300),
        "addresses_signals" => addressed_signals.first(6).map(&:label),
        "addresses_patterns" => addressed_patterns.first(4).map(&:title),
        "fit_confidence" => confidence.round(2),
        "reviewer_endorsed" => sol.reviewer_endorsed,
        "reviewer_note" => sol.reviewer_note.presence,
        "reviewer_name" => sol.reviewer_user&.name
      }
    end

    def tokenize(text)
      text.to_s.downcase.scan(/[a-z0-9]+/).reject { |t| t.length < 3 || STOPWORDS.include?(t) }.to_set
    end

    def overlap?(terms, label)
      label_terms = tokenize(label)
      (terms & label_terms).any?
    end
  end
end
