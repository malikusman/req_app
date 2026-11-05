# frozen_string_literal: true

module KeyPerson
  # Decides what the conversation does next (Doc 08 §9, §22; Doc 05 §2.2: the
  # platform owns state and decisions, the model owns content). It reads the
  # structured state and what P03 heard in the last answer, and returns the next
  # turn instruction for P02 — never the words.
  #
  # Pure: no model, no database. The state is a plain hash the caller stores in
  # ConversationSession#state_snapshot after every turn, so the conversation can
  # stop and start anywhere and be replayed in a spec.
  #
  # The rules, in the order they apply after each answer:
  #   1. a wish to pause or stop, or a question from the participant, comes first;
  #   2. a vague answer gets at most one follow-up on that area (§9.1A), never
  #      after the participant has gone into operational detail;
  #   3. one gentle clarification, per conversation, of a fact that contradicts
  #      the company profile (§20);
  #   4. the conversation closes at the ceiling, after a stall, or once coverage
  #      is sufficient and the floor is reached (§22);
  #   5. otherwise the next area is the most valuable one still open: Essential
  #      areas first (broad discovery), then the rest (focused exploration), with
  #      a short reflection every few questions (§9.5).
  # Closing is always: read-back, scope and participants, documents (if any
  # were mentioned), "anything else?", then the closing words (§13, §14, §23).
  class Planner
    QUESTION_MODES = %w[QUESTION FOLLOW_UP EXAMPLE CLARIFY REFLECT_AND_ASK RESUME].freeze
    CLOSING_MODES = %w[PRIORITY_READ_BACK SCOPE_AND_PARTICIPANTS DOCUMENT_REQUEST ANYTHING_ELSE CLOSING].freeze
    DEFAULT_LIMITS = { "floor" => 8, "ceiling" => 24, "stall" => 3 }.freeze
    REFLECT_EVERY = 4
    RECENT_QUESTIONS = 8
    SUMMARY_LINES = 16
    MAX_DOCUMENTS = 3

    FOLLOW_UP_NOTE = "Their last answer on this was too general to record. Ask one short follow-up on what they " \
                     "meant. This is the only follow-up on this topic."
    EXAMPLE_NOTE = "They stressed this but kept it general. Ask for one brief example."
    CONFUSED_NOTE = "They seemed unsure what was meant. Ask the same thing again, more simply."

    # Floor, ceiling and stall threshold: from the company's settings, then the
    # environment, then the defaults (Doc 06 §4.1).
    def self.limits_for(company)
      from_company = company&.merged_settings&.dig("key_person_limits") || {}
      DEFAULT_LIMITS.to_h do |key, default|
        value = from_company[key].presence || ENV["KEY_PERSON_#{key.upcase}"].presence || default
        [key, Integer(value)]
      end
    end

    def self.initial_snapshot
      {
        "coverage" => Coverage.blank_state,
        "phase" => "BROAD",
        "instruction" => nil,
        "paused_instruction" => nil,
        "closing_queue" => nil,
        "close_reason" => nil,
        "recent_questions" => [],
        "summary" => [],
        "participant_turns" => 0,
        "stall_count" => 0,
        "questions_since_reflection" => 0,
        "last_area" => nil,
        "clarify_used" => false,
        "documents_mentioned" => [],
        "participants_mentioned" => [],
        "contradictions" => []
      }
    end

    attr_reader :snapshot

    def initialize(snapshot:, persona:, limits: DEFAULT_LIMITS)
      @snapshot = self.class.initial_snapshot.merge(snapshot.to_h.deep_dup)
      @persona = persona.presence || "OTHER"
      @limits = DEFAULT_LIMITS.merge(limits.to_h.stringify_keys)
    end

    def instruction = @snapshot["instruction"]
    def coverage = @snapshot["coverage"]

    def opening
      set_instruction("mode" => "OPENING", "state" => "OPENING")
    end

    # Coming back after a pause or a long gap: a brief welcome, then the same
    # thread — never a restart (Doc 08 §24).
    def resume
      base = @snapshot["paused_instruction"] || instruction
      @snapshot["paused_instruction"] = nil
      return opening if base.nil? || base["mode"] == "OPENING"

      if base["target_domain"] && QUESTION_MODES.include?(base["mode"])
        set_instruction(base.merge("mode" => "RESUME", "thread_note" => nil, "reflection_note" => nil))
      else
        set_instruction(base.merge("resumed" => true))
      end
    end

    # The pause button: keep the current question for when they come back.
    def pause
      return instruction if instruction&.dig("mode") == "PAUSE"

      pause!(instruction || {})
    end

    # They answered straight after pausing, without the welcome-back turn: the
    # answer belongs to the question they paused on.
    def unpause
      return instruction unless instruction&.dig("mode") == "PAUSE"

      @snapshot["instruction"] = @snapshot["paused_instruction"]
      @snapshot["paused_instruction"] = nil
      instruction
    end

    # The participant has answered the current instruction. capture is the
    # validated P03 output, or nil when capture failed: then the target counts
    # as not filled (P03 §9) and the conversation carries on.
    def after_answer(capture)
      previous = instruction || {}
      @snapshot["participant_turns"] += 1
      improved = capture ? apply(capture, previous) : false
      @snapshot["stall_count"] = improved ? 0 : @snapshot["stall_count"] + 1

      signal = capture&.dig("participant_signal").presence || "NONE"
      question = capture&.dig("participant_question")

      return pause!(previous) if signal == "WANTS_PAUSE"

      start_closing!("PARTICIPANT_ENDED", short: true) if signal == "WANTS_END" && !closing?
      return aside!(previous, question) if question.is_a?(Hash) && question["asked"] == true
      return next_closing_step! if closing?

      if (decision = settle_previous_target(previous, capture, signal))
        return decision
      end
      if (clarify = clarify_contradiction)
        return clarify
      end

      return start_closing_and_continue!("CEILING") if @snapshot["participant_turns"] >= @limits["ceiling"]
      return start_closing_and_continue!("STALLED") if @snapshot["stall_count"] >= @limits["stall"]
      if @snapshot["participant_turns"] >= @limits["floor"] && Coverage.sufficient?(coverage, @persona)
        return start_closing_and_continue!("COVERAGE_COMPLETE")
      end

      area = next_area
      return start_closing_and_continue!("COVERAGE_COMPLETE") unless area

      ask!(area, reflection_due? ? "REFLECT_AND_ASK" : "QUESTION")
    end

    # Called with what the assistant actually said, so it is never asked again,
    # even reworded (Doc 08 §33).
    def record_question(text)
      return if text.blank? || %w[PAUSE CLOSING].include?(instruction&.dig("mode"))

      @snapshot["recent_questions"] = (@snapshot["recent_questions"] + [text.to_s.squish]).last(RECENT_QUESTIONS)
    end

    # Rough position for P02: early, middle or near the end.
    def progress
      return "near_end" if closing?

      essentials = Coverage::AREAS.select { |a| Coverage.weight(a, @persona) == Coverage::ESSENTIAL }
      done = essentials.count { |a| resolved?(coverage[a]) }
      done < (essentials.size * 0.4) ? "early" : "middle"
    end

    def closing? = @snapshot["closing_queue"].is_a?(Array)

    private

    def set_instruction(attrs)
      @snapshot["instruction"] = attrs.compact
    end

    # What the answer contributed, to every area it touched — people often answer
    # several things at once (P03 rule 2). Returns whether coverage improved.
    def apply(capture, previous)
      target = previous["target_domain"]
      improved = false

      Array(capture["domains_touched"]).each do |touched|
        entry = coverage[touched["domain"]]
        next unless entry

        if touched["contribution"] == "USABLE" && entry["status"] != "USABLE"
          entry.merge!("status" => "USABLE", "settled" => true)
          improved = true
        elsif touched["contribution"] == "PARTIAL" && entry["status"] == "OPEN"
          entry["status"] = "PARTIAL"
          improved = true
        end
      end

      result = capture["previous_target_result"]
      if target && coverage[target] && result.is_a?(Hash) && result["quality"] == "USABLE" &&
         coverage[target]["status"] != "USABLE"
        coverage[target].merge!("status" => "USABLE", "settled" => true)
        improved = true
      end

      Array(capture["statements"]).each do |statement|
        coverage[statement["domain"]]["emphasised"] = true if statement["importance_signal"] == "EMPHASISED" &&
                                                               coverage[statement["domain"]]
      end

      if Array(capture["planned_initiatives"]).any? && coverage["PLANNED_INITIATIVES"]["status"] != "USABLE"
        coverage["PLANNED_INITIATIVES"].merge!("status" => "USABLE", "settled" => true)
        improved = true
      end

      if capture["detail_overflow"] == true && target && coverage[target]
        entry = coverage[target]
        entry["overflow"] = true
        entry["settled"] = true
        entry["status"] = "PARTIAL" if entry["status"] == "OPEN"
      end

      remember(capture, target)
      improved
    end

    def remember(capture, target)
      if (line = capture["summary_update"].to_s.squish.presence)
        @snapshot["summary"] = (@snapshot["summary"] + [{ "area" => target || "GENERAL", "text" => line }])
                               .last(SUMMARY_LINES)
      end

      Array(capture["documents_mentioned"]).each do |doc|
        description = doc["description"].to_s.squish
        next if description.blank?
        next if @snapshot["documents_mentioned"].any? { |d| d["description"].casecmp?(description) }

        @snapshot["documents_mentioned"] << { "description" => description, "evidence" => doc["evidence"] }
      end

      Array(capture["participants_mentioned"]).each do |person|
        @snapshot["participants_mentioned"] << person.slice("name", "role", "department", "reason", "evidence")
      end

      Array(capture["profile_facts_discovered"]).each do |fact|
        next unless fact["contradicts_known"] == true

        @snapshot["contradictions"] << fact.slice("field", "value", "evidence").merge("clarified" => false)
      end
    end

    # The previous question's area after this answer: one follow-up when it was
    # vague, otherwise it is settled — usable, or kept as an unknown.
    def settle_previous_target(previous, capture, signal)
      target = previous["target_domain"]
      mode = previous["mode"] == "HANDLE_ASIDE" ? previous["return_mode"] : previous["mode"]
      return unless target && QUESTION_MODES.include?(mode)

      entry = coverage.fetch(target)
      return if entry["settled"]

      quality = capture&.dig("previous_target_result", "quality")
      if quality == "VAGUE" && !entry["follow_up_used"] && !entry["overflow"] && signal != "UNWILLING_ON_TOPIC"
        entry["follow_up_used"] = true
        return entry["emphasised"] ? ask!(target, "EXAMPLE", note: EXAMPLE_NOTE) : ask!(target, "FOLLOW_UP", note: FOLLOW_UP_NOTE)
      end
      return ask!(target, "CLARIFY", note: CONFUSED_NOTE) if signal == "CONFUSED" && mode != "CLARIFY"

      if signal == "UNWILLING_ON_TOPIC" || entry["follow_up_used"] || entry["asked"] >= 2 || quality == "VAGUE"
        entry["settled"] = true
        entry["status"] = "UNKNOWN" if entry["status"] == "OPEN"
      end
      nil
    end

    def clarify_contradiction
      return if @snapshot["clarify_used"]

      pending = @snapshot["contradictions"].find { |c| !c["clarified"] }
      return unless pending

      pending["clarified"] = true
      @snapshot["clarify_used"] = true
      set_instruction(
        "mode" => "CLARIFY", "state" => "CLARIFICATION", "target_domain" => nil,
        "intent" => "check, lightly, a company fact that differs from what we were told",
        "thread_note" => "They said the company's #{pending['field'].to_s.tr('_', ' ')} is \"#{pending['value']}\", " \
                         "which differs from what the company shared earlier. Ask, lightly and without " \
                         "challenging them, which is right today."
      )
    end

    def ask!(area, mode, note: nil)
      entry = coverage.fetch(area)
      entry["asked"] += 1 unless mode == "RESUME"
      @snapshot["last_area"] = area
      @snapshot["questions_since_reflection"] = mode == "REFLECT_AND_ASK" ? 0 : @snapshot["questions_since_reflection"] + 1
      @snapshot["phase"] = "FOCUSED" if @snapshot["phase"] == "BROAD" && essentials_all_raised?

      state = if mode == "CLARIFY" then "CLARIFICATION"
              elsif @snapshot["phase"] == "BROAD" then "BROAD_DISCOVERY"
              else "FOCUSED_EXPLORATION"
              end
      set_instruction(
        "mode" => mode, "state" => state, "target_domain" => area, "intent" => Intents.intent(area),
        "thread_note" => note,
        "reflection_note" => mode == "REFLECT_AND_ASK" ? reflection_note : nil
      )
    end

    def next_area
      candidates = Coverage::AREAS.reject { |a| resolved?(coverage[a]) }
      unraised = candidates.select do |a|
        Coverage.weight(a, @persona) == Coverage::ESSENTIAL && coverage[a]["asked"].zero?
      end
      pool = unraised.any? ? unraised : candidates
      pool -= [@snapshot["last_area"]] if pool.size > 1
      pool.max_by { |a| [score(a), -Coverage::AREAS.index(a)] }
    end

    def score(area)
      entry = coverage[area]
      (Coverage.weight(area, @persona) * 10) + (entry["status"] == "PARTIAL" ? 3 : 0) +
        (entry["emphasised"] ? 2 : 0) - (entry["asked"] * 6)
    end

    def resolved?(entry) = Coverage.resolved?(entry)

    def essentials_all_raised?
      Coverage::AREAS.all? do |a|
        Coverage.weight(a, @persona) != Coverage::ESSENTIAL || coverage[a]["asked"].positive? || resolved?(coverage[a])
      end
    end

    def reflection_due?
      @snapshot["questions_since_reflection"] >= REFLECT_EVERY - 1 && @snapshot["summary"].size >= 2
    end

    def reflection_note
      lines = @snapshot["summary"].last(2).map { |s| s["text"] }
      "Things they have said that you might connect, in one sentence, without concluding anything: " \
        "#{lines.join(' / ')}"
    end

    def pause!(previous)
      @snapshot["paused_instruction"] = previous.presence
      set_instruction("mode" => "PAUSE", "state" => "PAUSED")
    end

    # Answer their question briefly, then return to the same thread: the next
    # answer is graded against the same area.
    def aside!(previous, question)
      set_instruction(
        previous.except("reflection_note", "resumed").merge(
          "mode" => "HANDLE_ASIDE", "aside_topic" => question["topic"].presence || "OTHER",
          "aside_text" => question["text"].to_s.squish.truncate(300),
          "return_mode" => previous["mode"] == "HANDLE_ASIDE" ? previous["return_mode"] : previous["mode"]
        )
      )
    end

    def start_closing!(reason, short: false)
      queue = []
      queue << "PRIORITY_READ_BACK" if @snapshot["summary"].any?
      queue << "SCOPE_AND_PARTICIPANTS" unless short && queue.empty?
      queue << "DOCUMENT_REQUEST" if !short && @snapshot["documents_mentioned"].any?
      queue << "ANYTHING_ELSE" unless short
      queue << "CLOSING"
      @snapshot["closing_queue"] = queue
      @snapshot["close_reason"] = reason
    end

    def start_closing_and_continue!(reason)
      start_closing!(reason)
      next_closing_step!
    end

    def next_closing_step!
      mode = @snapshot["closing_queue"].shift || "CLOSING"
      attrs = { "mode" => mode, "state" => closing_state(mode) }
      attrs["target_domain"] = "PRIORITY_AREAS" if mode == "PRIORITY_READ_BACK"
      attrs["themes"] = read_back_themes if mode == "PRIORITY_READ_BACK"
      if mode == "DOCUMENT_REQUEST"
        attrs["documents"] = @snapshot["documents_mentioned"].first(MAX_DOCUMENTS).map { |d| d["description"] }
      end
      attrs["close_reason"] = @snapshot["close_reason"] if mode == "CLOSING"
      set_instruction(attrs)
    end

    # The themes to read back (Doc 08 §23): what they stressed first, then the
    # most recent, in the words captured.
    def read_back_themes
      emphasised = Coverage::AREAS.select { |a| coverage[a]["emphasised"] }
      lines = @snapshot["summary"].sort_by { |s| emphasised.include?(s["area"]) ? 0 : 1 }
      lines.first(6).map { |s| s["text"] }
    end

    def closing_state(mode)
      case mode
      when "PRIORITY_READ_BACK" then "PRIORITY_CONFIRMATION"
      when "SCOPE_AND_PARTICIPANTS" then "SCOPE_AND_PARTICIPANTS"
      when "CLOSING" then "COMPLETE"
      else "DOCUMENT_REQUEST"
      end
    end
  end
end
