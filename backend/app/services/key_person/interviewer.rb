# frozen_string_literal: true

module KeyPerson
  # Writes what the assistant says this turn (P02). The planner has already
  # decided what to ask; this decides how to say it, then Guard checks it before
  # anyone sees it.
  #
  # P02 §11: a reply that fails the checks, or a model that errors, gets one more
  # try; after that the platform asks the safe question for the area from the
  # intent library. The participant never sees an error and the conversation
  # never stalls. A pause gets a plain acknowledgement, with no model call.
  class Interviewer
    Reply = Struct.new(:text, :fallback_reason, keyword_init: true)

    ATTEMPTS = 2
    # Why the last draft was refused, in words P02 can act on.
    RETRY_NOTES = {
      "empty" => "Your last draft was empty.",
      "too_long" => "Your last draft was too long. Say it in fewer words.",
      "question_count" => "Your last draft did not ask exactly one question. Ask one thing.",
      "repeats_question" => "Your last draft repeated an earlier question. Ask something new.",
      "blocked_term" => "Your last draft used a word you must not bring up yourself (AI, automation, agents, price, " \
                        "reports, consultants, readiness, assessment). Leave it out.",
      "asks_known_fact" => "Your last draft asked for something the company already told us. Don't ask for it."
    }.freeze

    def self.system_prompt(pack, mode)
      base = Openai::Client.prompt("p00c_conversational_base.v1.txt").gsub("{{language}}", pack.language_instruction)
      rules, modes = parse_rules
      participant = pack.session.participant
      rules = rules.gsub("{{participant_name}}", pack.clean(participant.name))
                   .gsub("{{participant_role}}", pack.clean(participant.role_title.presence || "key person"))
                   .gsub("{{persona}}", pack.persona.humanize.downcase)
      block_key = mode == "OPENING" && !Personas.company_wide?(pack.persona) ? "OPENING_DEPARTMENT" : mode
      [base.strip, rules.strip, "THIS TURN'S MODE: #{mode}\n#{modes.fetch(block_key, '')}".strip].join("\n\n")
    end

    # The engine rules, and the per-mode blocks after each "@@ MODE" marker.
    def self.parse_rules
      @parse_rules ||= begin
        text = Openai::Client.prompt("p02_key_person_interviewer.v1.txt")
        rules, *blocks = text.split(/^@@ /)
        [rules, blocks.to_h { |b| [b.lines.first.strip, b.lines.drop(1).join.strip] }]
      end
    end

    def initialize(session:, planner:, pack:, client: Openai::Client.new)
      @session = session
      @planner = planner
      @pack = pack
      @client = client
      @instruction = planner.instruction
      @mode = @instruction.fetch("mode")
    end

    def call
      return Reply.new(text: Intents.line("PAUSE", @pack.language)) if @mode == "PAUSE"

      log = RunLog.new(session: @session, stage: "P02",
                       prompt_version: Openai::Client::KEY_PERSON_INTERVIEWER_PROMPT_VERSION,
                       context_classes: @pack.context_classes)
      return fallback(log, "model_off") unless Llm::KeyPerson.enabled? && @client.configured?
      return fallback(log, "model_unavailable") if OpenaiCircuitBreaker.open?

      reason = nil
      ATTEMPTS.times do |attempt|
        result = @client.key_person_turn(system: self.class.system_prompt(@pack, @mode), context: context(reason))
        log.add(result)
        text = tidy(result.content)
        reason = Guard.check(text, mode: @mode, recent_questions: @planner.snapshot["recent_questions"],
                                   known_fields: @pack.known_fields, participant_text: @pack.recent_participant_text)
        if reason.nil?
          log.record!(status: attempt.zero? ? "OK" : "RETRIED")
          return Reply.new(text: text)
        end
      rescue Openai::Client::Error, Timeout::Error, SystemCallError, IOError => e
        Rails.logger.warn("[KeyPerson::Interviewer] session=#{@session.id} #{e.class}: #{e.message}")
        reason = "model_error"
      end
      fallback(log, reason)
    end

    private

    def context(reason)
      blocks = [
        @pack.participant_block, @pack.known_facts_block, @pack.consultant_focus_block,
        @pack.summary_block(@planner.snapshot["summary"]),
        @pack.recent_questions_block(@planner.snapshot["recent_questions"]),
        @pack.recent_turns_block,
        "<progress trust=\"platform\">#{@planner.progress}</progress>",
        turn_instruction
      ]
      note = RETRY_NOTES[reason.to_s.split(":").first]
      blocks << note if note
      blocks.join("\n\n")
    end

    def turn_instruction
      lines = ["THIS TURN", "Mode: #{@mode}"]
      if (area = @instruction["target_domain"])
        lines << "Target: #{area} — #{@instruction['intent'] || Intents.intent(area)}"
      end
      lines << "Note: #{@instruction['thread_note']}" if @instruction["thread_note"]
      lines << "Reflection note: #{@instruction['reflection_note']}" if @instruction["reflection_note"]
      lines << "They have just come back after a break: welcome them back briefly first." if @instruction["resumed"]
      if @instruction["themes"].present?
        lines << "Themes:"
        lines.concat(@instruction["themes"].map { |t| "- #{t}" })
      end
      if @instruction["documents"].present?
        lines << "Documents:"
        lines.concat(@instruction["documents"].map { |d| "- #{@pack.clean(d)}" })
      end
      if @mode == "HANDLE_ASIDE"
        lines << "Their question (#{@instruction['aside_topic']}): #{@pack.clean(@instruction['aside_text'])}"
      end
      lines << "Write only what you will say now, in #{@pack.language_instruction}."
      lines.join("\n")
    end

    # Models sometimes wrap a line in quotes or label it; the participant should
    # see only the words.
    def tidy(content)
      content.to_s.strip.sub(/\A(assistant|mjadi)\s*:\s*/i, "").gsub(/\A["“”']+|["“”']+\z/, "").squish
    end

    def fallback(log, reason)
      log.record!(status: "FALLBACK", fallback_reason: reason)
      Reply.new(text: fallback_text, fallback_reason: reason)
    end

    def fallback_text
      lang = @pack.language
      area = @instruction["target_domain"]
      case @mode
      when "RESUME"
        [Intents.line("RESUME", lang), area && Intents.question(area, lang)].compact.join(" ")
      when "HANDLE_ASIDE"
        back_to = @instruction["return_mode"]
        thread = if area then Intents.question(area, lang)
                 elsif Planner::CLOSING_MODES.include?(back_to) then Intents.line(back_to, lang)
                 end
        [Intents.line("HANDLE_ASIDE", lang), thread].compact.join(" ")
      when *Planner::QUESTION_MODES
        area ? Intents.question(area, lang) : Intents.line("CLARIFY", lang)
      else
        Intents.line(@mode, lang)
      end
    end
  end
end
