# frozen_string_literal: true

module KeyPerson
  # Checks what P02 wrote before the participant sees it (P02 §12). Returns nil
  # when it may be said, or the reason it may not; the interviewer then
  # regenerates once and, failing that, asks the safe question for the area.
  #
  # Words the conversation must never bring up itself — AI, automation, price,
  # reports — are allowed back only when the participant used them first: an
  # owner who talks about their own prices or their weekly sales report must be
  # able to hear those words. Words about Mjadi's own process (consultants,
  # readiness, assessment) are never said (P00-C rule 9).
  module Guard
    MAX_WORDS = {
      "OPENING" => 130, "PRIORITY_READ_BACK" => 100, "CLOSING" => 75, "DOCUMENT_REQUEST" => 75,
      "HANDLE_ASIDE" => 60, "RESUME" => 55
    }.freeze
    DEFAULT_MAX_WORDS = 45
    # These may hold no question, or a closing one or two; every other turn asks
    # exactly one thing (P02 rule 11).
    FREE_QUESTION_MODES = %w[OPENING CLOSING PRIORITY_READ_BACK].freeze
    # Coming back to the same thread — after a break, a question of theirs, or a
    # simpler rewording — is meant to ask the same thing again.
    SAME_THREAD_MODES = %w[RESUME HANDLE_ASIDE CLARIFY].freeze

    NEVER = [
      /\b(consultants?|consultancy|readiness|assessments?)\b/i,
      /مستشار|جاهزية|تقييم/
    ].freeze

    # name => [English pattern, Arabic pattern]
    UNLESS_THEY_SAID = {
      "ai" => [/\b(ai|a\.i\.|artificial intelligence|machine learning|chatgpt|chatbots?|llms?)\b/i,
               /الذكاء الاصطناعي|ذكاء اصطناعي/],
      "automation" => [/\bautomat(e|ed|es|ing|ion)\b/i, /أتمتة|الأتمتة|آلياً/],
      "agent" => [/\bagents?\b/i, /وكيل ذكي|وكلاء أذكياء/],
      "price" => [/\b(price|prices|pricing|fees?|contracts?|pay|paying|budgets?)\b|\bcost of (this|the) (work|engagement)\b/i,
                  /سعر|أسعار|تسعير|رسوم|عقد|ميزانية|تدفع/],
      "report" => [/\breports?\b/i, /تقرير|تقارير/],
      "score" => [/\bscor(e|es|ing)\b/i, /درجة|نقاط/]
    }.freeze

    # A question asking for something the company already told us (Doc 08 §2,
    # P02 rule 1). Checked only for fields the profile actually holds.
    KNOWN_FACT_QUESTIONS = {
      "industry" => /\b(what|which) (industry|sector)\b|ما (هو )?(القطاع|المجال) الذي/i,
      "products_services" => /\bwhat (do|does) (you|the (company|business)) (sell|make|offer)\b|\bwhat products\b/i,
      "locations" => /\bwhere (are you|is the (company|business)) (based|located)\b|\bwhich (countries|cities) (are you|do you)\b/i,
      "size_band" => /\bhow many (people|staff|employees) (do you have|work)\b|كم عدد (الموظفين|العاملين)/i,
      "business_model" => /\bdo you sell (mainly )?to (businesses|consumers)\b/i,
      "customer_channels" => /\bhow do (customers|clients) (reach|contact|order from) you\b/i,
      "org_departments" => /\b(what|which) departments (do you have|are there)\b/i,
      "known_systems" => /\bwhat (systems|software) (do you|does your (team|company)) use\b/i
    }.freeze

    STOPWORDS = %w[what where which would your have that this there does with from they them about when could most
                   more like into been were will just really their than then those these some something].freeze
    SIMILAR = 0.6

    module_function

    def check(text, mode:, recent_questions: [], known_fields: [], participant_text: "")
      said = text.to_s.squish
      return "empty" if said.blank?
      return "too_long" if said.split.size > MAX_WORDS.fetch(mode, DEFAULT_MAX_WORDS)

      questions = said.count("?") + said.count("؟")
      if FREE_QUESTION_MODES.include?(mode)
        return "question_count" if questions > 2
      elsif questions != 1
        return "question_count"
      end

      blocked = blocked_term(said, mode, participant_text)
      return "blocked_term:#{blocked}" if blocked
      return "repeats_question" if !SAME_THREAD_MODES.include?(mode) && repeats?(said, recent_questions)

      field = asks_known_fact(said, known_fields)
      return "asks_known_fact:#{field}" if field

      nil
    end

    def blocked_term(said, mode, participant_text)
      return "process" if NEVER.any? { |pattern| said.match?(pattern) }

      UNLESS_THEY_SAID.each do |name, patterns|
        next if name == "report" && mode == "DOCUMENT_REQUEST"
        next unless patterns.any? { |p| said.match?(p) }
        next if patterns.any? { |p| participant_text.to_s.match?(p) }

        return name
      end
      nil
    end

    # A new question mustn't repeat an earlier one, even reworded (P02 rule 10).
    def repeats?(said, recent_questions)
      words = significant_words(said)
      return false if words.size < 3

      Array(recent_questions).any? do |earlier|
        other = significant_words(earlier)
        next false if other.empty?

        (words & other).size.to_f / (words | other).size >= SIMILAR
      end
    end

    def asks_known_fact(said, known_fields)
      Array(known_fields).find { |field| KNOWN_FACT_QUESTIONS[field]&.match?(said) }
    end

    def significant_words(text)
      text.to_s.downcase.scan(/[[:alnum:]]+/).select { |w| w.length > 3 }.uniq - STOPWORDS
    end
  end
end
