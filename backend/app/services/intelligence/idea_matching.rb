# frozen_string_literal: true

module Intelligence
  # Whether two idea titles name the same idea. Each regeneration asks a model for
  # ideas afresh, and it words the same idea differently every time — "Auto-
  # DataSync Assistant", "SmartDataSync Agent", "Auto-Data Sync Bot" — so matching
  # on the exact title let one company collect 169 ideas, most of them repeats.
  #
  # A title is reduced to its key words: camelCase split, the generic words every
  # idea carries (agent, bot, assistant, smart, AI…) dropped, and each word cut to
  # a short stem so "reconciliation" meets "reconciler". Two titles sharing at
  # least half their key words are the same idea. Deterministic on purpose: the
  # same titles always give the same answer, and a test can say why.
  module IdeaMatching
    GENERIC = %w[
      agent agentic agents bot bots assistant assist copilot automation automated automator automate auto ai
      smart intelligent tool workflow system systems for the and of to a an around across with driven based
      powered orchestrator coordinator helper engine hub accelerator enhancer optimizer optimization
    ].freeze
    # Abbreviations models use for the same word.
    SYNONYMS = { "ops" => "operations", "dept" => "department", "depts" => "department", "comm" => "communication",
                 "comms" => "communication", "recon" => "reconciliation", "interdept" => "department",
                 "crossdept" => "department", "fin" => "finance", "approvals" => "approval" }.freeze
    STEM = 5
    THRESHOLD = 0.5

    module_function

    def key_words(title)
      words = title.to_s.gsub(/([a-z])([A-Z])/, '\1 \2').downcase.gsub(/[^a-z0-9]+/, " ").split
      words.map { |w| SYNONYMS.fetch(w, w) }.reject { |w| GENERIC.include?(w) }
           .map { |w| w[0, STEM] }.reject { |w| GENERIC.include?(w) }.uniq
    end

    def same?(a, b)
      x = key_words(a)
      y = key_words(b)
      return false if x.empty? || y.empty?

      (x & y).size.to_f / (x | y).size >= THRESHOLD
    end
  end
end
