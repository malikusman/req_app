# frozen_string_literal: true

module KeyPerson
  # Records what the participant's answer contained (P03), as a separate call
  # from the conversation (Doc 05 §3.4) because the planner acts on it.
  #
  # The model records; code decides what is kept (P03 §10):
  #   - enums checked, anything unknown dropped or set to its neutral value;
  #   - every item cites this turn, never another;
  #   - a statement criticising a named person is moved to "sensitive", so it
  #     can never reach the running summary or the next prompt;
  #   - numbers kept exactly as said; fact status is always REPORTED;
  #   - only real profile fields may be proposed as discovered facts.
  #
  # When capture fails — no model, an error, JSON that won't parse twice — it
  # returns nil, and the planner treats the target as not filled (P03 §9):
  # wrongly marking an area covered means it is never asked about; wrongly
  # leaving it open costs one more question.
  class Capture
    DOMAINS = Coverage::AREAS
    QUALITIES = %w[USABLE VAGUE NONE].freeze
    CONTRIBUTIONS = %w[USABLE PARTIAL].freeze
    SYMPTOM_OR_CAUSE = %w[SYMPTOM SUSPECTED_CAUSE NEITHER].freeze
    IMPORTANCE = %w[EMPHASISED MENTIONED].freeze
    INITIATIVE_TYPES = %w[ERP CRM SYSTEM_REPLACEMENT RESTRUCTURE HIRING OUTSOURCING DIGITISATION POLICY_CHANGE OTHER].freeze
    SENSITIVE_TYPES = %w[CRITICISM_OF_PERSON RESTRUCTURING CONFIDENTIAL_STRATEGY LEGAL_OR_REGULATORY PERSONAL].freeze
    POSTURE_TYPES = %w[AI_TOOL_USE SHADOW_AI INTEGRATION_LEVEL TECHNICAL_CAPABILITY DATA_ACCESSIBILITY].freeze
    QUESTION_TOPICS = %w[PRICE AI_CAPABILITY DATA_USE PROCESS OTHER].freeze
    SIGNALS = %w[NONE WANTS_PAUSE WANTS_END CONFUSED UNWILLING_ON_TOPIC].freeze
    PROFILE_FIELDS = Companies::ProfileUpdater::PROFILE_KEYS
    # Words that make a sentence about a named person a criticism of them.
    CRITICAL = Regexp.union(
      /\b(never|late|slow|lazy|problem|fault|blame|useless|incompetent|careless|mistakes?|doesn'?t|don'?t|won'?t|
          can'?t|fails?|failing|messes|forgets?|ignores?|poor|weak|bad)\b/xi,
      /لا يقوم|متأخر|بطيء|كسول|مشكلة|خطأ|يفشل|يهمل/
    )

    def initialize(session:, turn:, previous_instruction:, planner:, pack:, client: Openai::Client.new)
      @session = session
      @turn = turn
      @previous = previous_instruction || {}
      @planner = planner
      @pack = pack
      @client = client
    end

    def call
      log = RunLog.new(session: @session, stage: "P03", subject: @turn,
                       prompt_version: Openai::Client::KEY_PERSON_CAPTURE_PROMPT_VERSION,
                       context_classes: @pack.context_classes)
      return failed(log, "model_off") unless Llm::KeyPerson.enabled? && @client.configured?
      return failed(log, "model_unavailable") if OpenaiCircuitBreaker.open?

      raw = nil
      2.times do |attempt|
        result = @client.key_person_capture(system: self.class.system_prompt, context: context)
        log.add(result)
        raw = @client.parse_reply(result.content)
        break if raw.is_a?(Hash)
      rescue JSON::ParserError
        next if attempt.zero?
      end
      return failed(log, "unusable_reply") unless raw.is_a?(Hash)

      captured = self.class.validate(raw, turn_id: @turn.locator, known_names: known_names)
      log.record!(status: log_status(log))
      captured
    rescue Openai::Client::Error, Timeout::Error, SystemCallError, IOError => e
      Rails.logger.warn("[KeyPerson::Capture] session=#{@session.id} #{e.class}: #{e.message}")
      failed(log, "model_error")
    end

    def self.system_prompt
      [Openai::Client.prompt("p00a_analytical_base.v1.txt").strip,
       Openai::Client.prompt("p03_key_person_turn_capture.v1.txt").strip].join("\n\n")
    end

    def self.validate(raw, turn_id:, known_names: [])
      sensitive = list(raw["sensitive"]).filter_map do |s|
        next unless s["note"].present?

        { "type" => enum(s["type"], SENSITIVE_TYPES, "PERSONAL"), "note" => text(s["note"]), "evidence" => turn_id }
      end

      statements = []
      list(raw["statements"]).each do |s|
        next unless DOMAINS.include?(s["domain"]) && s["statement"].present?
        next unless cites?(s["evidence"], turn_id)

        statement = {
          "domain" => s["domain"], "statement" => text(s["statement"]),
          "original_wording" => text(s["original_wording"]), "subject_area" => text(s["subject_area"]).presence,
          "is_symptom_or_cause" => enum(s["is_symptom_or_cause"], SYMPTOM_OR_CAUSE, "NEITHER"),
          "importance_signal" => enum(s["importance_signal"], IMPORTANCE, "MENTIONED"),
          "fact_status" => "REPORTED", "evidence" => turn_id
        }
        if criticises_someone?(statement, known_names)
          sensitive << { "type" => "CRITICISM_OF_PERSON", "note" => statement["statement"], "evidence" => turn_id }
        else
          statements << statement
        end
      end

      result = raw["previous_target_result"].is_a?(Hash) ? raw["previous_target_result"] : {}
      question = raw["participant_question"].is_a?(Hash) ? raw["participant_question"] : {}

      {
        "turn_id" => turn_id,
        "previous_target_result" => {
          "domain" => DOMAINS.include?(result["domain"]) ? result["domain"] : nil,
          "quality" => enum(result["quality"], QUALITIES, "NONE"),
          "reason" => text(result["reason"])
        },
        "domains_touched" => list(raw["domains_touched"]).filter_map do |d|
          next unless DOMAINS.include?(d["domain"])

          { "domain" => d["domain"], "contribution" => enum(d["contribution"], CONTRIBUTIONS, "PARTIAL") }
        end.uniq { |d| d["domain"] },
        "statements" => statements,
        "planned_initiatives" => cited(raw["planned_initiatives"], turn_id).filter_map do |i|
          next if i["description"].blank?

          { "type" => enum(i["type"], INITIATIVE_TYPES, "OTHER"), "description" => text(i["description"]),
            "timing" => text(i["timing"]).presence, "affected_areas" => Array(i["affected_areas"]).map { |a| text(a) },
            "evidence" => turn_id }
        end,
        "participants_mentioned" => cited(raw["participants_mentioned"], turn_id).map do |p|
          { "name" => text(p["name"]).presence, "role" => text(p["role"]).presence,
            "department" => text(p["department"]).presence, "reason" => text(p["reason"]), "evidence" => turn_id }
        end,
        "documents_mentioned" => cited(raw["documents_mentioned"], turn_id).filter_map do |d|
          { "description" => text(d["description"]), "evidence" => turn_id } if d["description"].present?
        end,
        "profile_facts_discovered" => cited(raw["profile_facts_discovered"], turn_id).filter_map do |f|
          next unless PROFILE_FIELDS.include?(f["field"]) && f["value"].present?

          { "field" => f["field"], "value" => text(f["value"]), "contradicts_known" => f["contradicts_known"] == true,
            "evidence" => turn_id }
        end,
        "numbers_mentioned" => cited(raw["numbers_mentioned"], turn_id).filter_map do |n|
          { "value" => n["value"].to_s.strip, "refers_to" => text(n["refers_to"]), "evidence" => turn_id } if n["value"].present?
        end,
        "sensitive" => sensitive,
        "political_signals" => cited(raw["political_signals"], turn_id).filter_map do |s|
          { "note" => text(s["note"]), "evidence" => turn_id } if s["note"].present?
        end,
        "posture_signals" => cited(raw["posture_signals"], turn_id).filter_map do |s|
          next unless POSTURE_TYPES.include?(s["type"])

          { "type" => s["type"], "note" => text(s["note"]), "evidence" => turn_id }
        end,
        "participant_question" => {
          "asked" => question["asked"] == true,
          "topic" => question["asked"] == true ? enum(question["topic"], QUESTION_TOPICS, "OTHER") : nil,
          "text" => question["asked"] == true ? text(question["text"]).presence : nil
        },
        "participant_signal" => enum(raw["participant_signal"], SIGNALS, "NONE"),
        "detail_overflow" => raw["detail_overflow"] == true,
        "summary_update" => summary_without_names(raw["summary_update"], known_names, sensitive)
      }
    end

    def self.list(value) = Array(value).select { |v| v.is_a?(Hash) }

    # Items must cite this turn. An item citing nothing is taken as this turn's;
    # one citing another turn is dropped (P03 §10).
    def self.cited(value, turn_id) = list(value).select { |v| cites?(v["evidence"], turn_id) }

    def self.cites?(evidence, turn_id) = evidence.blank? || evidence.to_s == turn_id

    def self.enum(value, allowed, default)
      candidate = value.to_s.strip.upcase
      allowed.include?(candidate) ? candidate : default
    end

    def self.text(value) = value.to_s.squish.truncate(500)

    def self.criticises_someone?(statement, known_names)
      words = "#{statement['statement']} #{statement['original_wording']}"
      named = Array(known_names).any? { |name| words.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i) }
      named && words.match?(CRITICAL)
    end

    # The summary feeds the next prompts, so it mustn't carry a criticised
    # person's name either. When the answer criticised someone, the summary
    # falls back to the neutral statements' gist by dropping any line naming them.
    def self.summary_without_names(summary, known_names, sensitive)
      line = text(summary).truncate(300)
      return line unless sensitive.any? { |s| s["type"] == "CRITICISM_OF_PERSON" }

      Array(known_names).any? { |name| line.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i) } ? nil : line
    end

    private

    def context
      [
        @pack.participant_block, @pack.known_facts_block,
        @pack.coverage_block(@planner.coverage), @pack.summary_block(@planner.snapshot["summary"]),
        previous_question_block, @pack.answer_block(@turn), "Record this answer now."
      ].join("\n\n")
    end

    def previous_question_block
      area = @previous["target_domain"]
      asked = @session.history.from_assistant.where("turn_index < ?", @turn.turn_index).last
      target = area ? "#{area} — #{@previous['intent'] || Intents.intent(area)}" : "none (#{@previous['mode'] || 'OPENING'})"
      "<previous_question trust=\"platform\">\ntarget: #{target}\nquestion: #{@pack.clean(asked&.text)}\n</previous_question>"
    end

    # People this conversation could name: those planned to take part, the key
    # user, and anyone the company has invited. First names count too, since
    # that is how managers usually refer to staff.
    def known_names
      engagement = @session.engagement
      names = engagement.participants.pluck(:name) + [engagement.key_user&.name] +
              @session.company.employees.pluck(:display_name)
      names.compact.flat_map { |n| [n, n.split.first] }.map(&:to_s).map(&:strip).select { |n| n.length >= 3 }.uniq
    end

    def log_status(log) = log.calls > 1 ? "RETRIED" : "OK"

    def failed(log, reason)
      log.record!(status: "FAILED", fallback_reason: reason)
      nil
    end
  end
end
