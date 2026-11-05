# frozen_string_literal: true

module KeyPerson
  # One step of a conversation with leadership: the opening, an answer and the
  # reply to it, a pause, or a welcome back. For an answer:
  #
  #   1. the answer is saved first, on its own, so nothing a participant says is
  #      lost to a failure later in the turn (Doc 14 §8);
  #   2. P03 records what it contained;
  #   3. what it means for the company profile and for consultant review is
  #      applied (Effects);
  #   4. the planner decides the next turn and P02 words it;
  #   5. the reply, the new state and the snapshot are saved together.
  #
  # Each session is locked while a turn is worked out, so two open tabs can't
  # interleave. When a later answer arrived meanwhile, only the latest is
  # answered.
  class Turn
    class Closed < StandardError; end
    class NotStarted < StandardError; end

    ARABIC = /\p{Arabic}/
    LETTER = /\p{L}/

    def initialize(session, client: Openai::Client.new)
      @session = session
      @client = client
    end

    # The first thing the assistant says, once consent is recorded.
    def open!
      @session.with_lock do
        planner = planner_for
        planner.opening
        speak!(planner)
      end
    end

    # A returning participant gets a brief welcome and the same thread (Doc 08 §24).
    def resume!
      @session.with_lock do
        raise Closed if @session.finished?

        planner = planner_for
        planner.resume
        speak!(planner)
      end
    end

    def pause!
      @session.with_lock do
        raise Closed if @session.finished?
        return @session if @session.paused?

        planner = planner_for
        planner.pause
        speak!(planner)
      end
    end

    # Returns the turns this answer added, oldest first.
    def answer!(text:, client_message_id: nil, input_mode: "TEXT")
      answer, repeated = save_answer!(text, client_message_id, input_mode)
      return @session.turns.where("turn_index >= ?", answer.turn_index).to_a if repeated

      @session.with_lock do
        later = @session.turns.from_participant.where("turn_index > ?", answer.turn_index).exists?
        return @session.turns.where("turn_index >= ?", answer.turn_index).to_a if later

        planner = planner_for
        previous = planner.unpause
        pack = ContextPack.new(@session)
        capture = Capture.new(session: @session, turn: answer, previous_instruction: previous, planner: planner,
                              pack: pack, client: @client).call
        Effects.new(@session, capture, answer).call
        if previous&.dig("mode") == "DOCUMENT_REQUEST" && capture&.dig("participant_signal") == "UNWILLING_ON_TOPIC"
          Documents.new(@session).decline_open!
        end
        planner.after_answer(capture)
        answer.update!(capture: capture, slots_filled: slots_filled(capture, previous))
        speak!(planner)
      end
      @session.turns.where("turn_index >= ?", answer.turn_index).to_a
    end

    private

    def planner_for
      Planner.new(snapshot: @session.state_snapshot, persona: @session.participant.persona,
                  limits: @session.limits.presence || Planner.limits_for(@session.company))
    end

    def save_answer!(text, client_message_id, input_mode)
      @session.with_lock do
        raise Closed if @session.finished?
        raise NotStarted if %w[NOT_STARTED CONSENT].include?(@session.state)

        # The same message sent twice (a double tap, a retry after a dropped
        # connection) is answered once.
        if client_message_id.present? &&
           (existing = @session.turns.find_by(client_message_id: client_message_id))
          return [existing, true]
        end

        @session.language = language_of(text) || @session.language
        @session.modality = "MIXED" if input_mode == "VOICE_NOTE"
        @session.last_activity_at = Time.current
        @session.save!
        turn = @session.turns.create!(turn_index: @session.next_turn_index, direction: "PARTICIPANT",
                                      text: text.to_s.strip, input_mode: input_mode,
                                      client_message_id: client_message_id.presence)
        [turn, false]
      end
    end

    # The assistant answers in the language the participant last wrote in:
    # Modern Standard Arabic for Arabic, English otherwise (Doc 08 §26). A
    # message with no letters (a number, a yes) leaves the language as it was.
    def language_of(text)
      letters = text.to_s.scan(LETTER)
      return nil if letters.size < 3

      letters.count { |l| l.match?(ARABIC) } > letters.size / 2 ? "ar" : "en"
    end

    # Graded against the previous question's target, not the next one (Doc 08 §33).
    def slots_filled(capture, previous)
      return [] unless capture

      target = previous&.dig("target_domain")
      usable = capture["domains_touched"].select { |d| d["contribution"] == "USABLE" }.pluck("domain")
      usable << target if target && capture.dig("previous_target_result", "quality") == "USABLE"
      usable.uniq
    end

    def speak!(planner)
      pack = ContextPack.new(@session)
      reply = Interviewer.new(session: @session, planner: planner, pack: pack, client: @client).call
      planner.record_question(reply.text)
      instruction = planner.instruction
      now = Time.current

      turn = @session.turns.create!(
        turn_index: @session.next_turn_index, direction: "AI", text: reply.text, mode: instruction["mode"],
        targeted_slot: instruction["target_domain"], fallback_reason: reply.fallback_reason,
        routing_decision: instruction.slice("mode", "target_domain", "state", "close_reason")
                                     .merge("progress" => planner.progress)
      )

      @session.move_to(instruction["state"], at: now)
      if instruction["mode"] == "CLOSING"
        @session.close_reason = instruction["close_reason"] || "COVERAGE_COMPLETE"
        @session.completed_at = now
      end
      @session.update!(state_snapshot: planner.snapshot, turn_count: @session.turns.count, last_activity_at: now)
      sync_participant!
      Documents.new(@session).open_requests!(instruction) if instruction["mode"] == "DOCUMENT_REQUEST"
      Completion.call(@session) if @session.state == "COMPLETE"
      turn
    end

    def sync_participant!
      status = case @session.state
               when "COMPLETE" then "COMPLETED"
               when "PAUSED" then "PAUSED"
               else "STARTED"
               end
      participant = @session.participant
      participant.update!(participation_status: status) if participant.participation_status != status
    end
  end
end
