# frozen_string_literal: true

module Synthesis
  # Stage B: which pairs of work items are worth asking P10 about (Doc 10 §7,
  # §20.1). Cheap structured signals first; the model only ever judges pairs
  # this has already found plausible (P10 §2).
  #
  # A similar title is never enough on its own (Doc 10 §9.1, §21): two "weekly
  # reports" may serve different purposes. A pair is shortlisted only when
  # something beyond the name connects it — the work itself, a system, the same
  # figures given twice, or the platform's own duplicate flag.
  #
  # ProcessClusters::Relationship compares the same pairs by rules on each
  # task's trigger, output and steps. Those rules are to become this shortlist
  # and settle the clear cases before P10 (docs/CONSOLIDATION_ENGINES.md §3).
  class Candidates
    Pair = Struct.new(:a, :b, :score, :signals, :digest, keyword_init: true)

    # Weights follow Doc 10 §20.1: purpose and object high, systems medium-high,
    # department and cadence medium, the task name alone low.
    STRONG_OVERLAP = 0.25
    SOME_OVERLAP = 0.12
    THRESHOLD = 2.0
    # Bounds the model calls per run; typical engagements hold 30–60 items.
    MAX_PAIRS = 80

    def self.digest_for(a, b)
      first, second = [a, b].sort_by(&:id)
      Digest::SHA256.hexdigest([first.id, first.digest, second.id, second.digest].join("|"))
    end

    def self.call(items, skip_digests: Set.new) = new(items, skip_digests).call

    def initialize(items, skip_digests)
      @items = items
      @skip = skip_digests
    end

    def call
      @items.combination(2).filter_map { |a, b| pair(a, b) }
            .reject { |p| @skip.include?(p.digest) }
            .sort_by { |p| [-p.score, p.a.id, p.b.id] }
            .first(MAX_PAIRS)
    end

    private

    def pair(a, b)
      a, b = [a, b].sort_by(&:id)
      signals = []
      score = 0.0
      substance = false

      if a.duplicate_of_id == b.id || b.duplicate_of_id == a.id
        score += 3
        substance = true
        signals << "The same person gave the same figures for both"
      end

      overlap = Findings::Words.overlap(a.words, b.words)
      if overlap >= STRONG_OVERLAP
        score += 2
        substance = true
        signals << "Describe the same kind of work (#{shared_words(a, b)})"
      elsif overlap >= SOME_OVERLAP
        score += 1
        substance = true
        signals << "Overlapping description (#{shared_words(a, b)})"
      end

      shared_systems = a.systems & b.systems
      if shared_systems.any?
        score += 1.5
        substance = true
        signals << "Both use #{shared_systems.join(', ')}"
      end

      if same_figures?(a, b) && a.employee_id != b.employee_id
        score += 1
        signals << "Same frequency and duration"
      end

      same_department = a.department.present? && a.department.casecmp?(b.department.to_s)
      if same_department
        score += 1
        signals << "Same department"
      end
      if a.role.present? && a.role.casecmp?(b.role.to_s)
        score += 0.5
        signals << "Same role title"
        # Several people in one role in one department are the likeliest to
        # describe the same work in different words (P10 §7.1) — worth asking
        # about, and the same-title trap is P10's to rule out, not ours.
        if same_department && a.employee_id != b.employee_id
          score += 1
          substance = true
        end
      end
      if Findings::Words.overlap(a.title_words, b.title_words) >= STRONG_OVERLAP
        score += 0.5
        signals << "Similar names"
      end

      return unless substance && score >= THRESHOLD

      # Who described each — never by name. Without it P10 cannot tell one
      # person's two accounts of one task from two people's own work.
      signals << (a.employee_id && a.employee_id == b.employee_id ? "Both described by the same person" :
                                                                    "Described by two different people")
      Pair.new(a: a, b: b, score: score, signals: signals, digest: self.class.digest_for(a, b))
    end

    def shared_words(a, b) = (a.words & b.words).first(4).join(", ")

    def same_figures?(a, b)
      a.hours? && b.hours? && a.hours_min == b.hours_min && a.hours_max == b.hours_max
    end
  end
end
