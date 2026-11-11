# frozen_string_literal: true

module Engagements
  # The one way an engagement's status changes. Checks the move is allowed and its
  # preconditions hold, then records who made it and why in status_history (and in
  # the platform audit log when a Mjadi user made it).
  #
  # A platform user may force a move the normal path doesn't allow — say, closing
  # an engagement early — but only with a reason, which is kept.
  class Transition
    class Error < StandardError; end

    ALLOWED = {
      "SET_UP" => %w[ONBOARDING],
      "ONBOARDING" => %w[KEY_PERSON_DISCOVERY],
      "KEY_PERSON_DISCOVERY" => %w[STAGE_1_PRICING],
      "STAGE_1_PRICING" => %w[STAGE_1_ACTIVE CLOSED],
      "STAGE_1_ACTIVE" => [],
      "CLOSED" => []
    }.freeze

    def self.call(engagement:, to:, actor: nil, reason: nil, force: false, request: nil)
      new(engagement: engagement, to: to, actor: actor, reason: reason, force: force, request: request).call
    end

    def initialize(engagement:, to:, actor:, reason:, force:, request:)
      @engagement = engagement
      @to = to.to_s
      @actor = actor
      @reason = reason.to_s.strip.presence
      @force = force
      @request = request
    end

    def call
      from = @engagement.status
      return @engagement if from == @to

      check_allowed!(from)
      check_preconditions!

      moved = false
      @engagement.with_lock do
        # The lock reloads the row. Someone may have moved it in the meantime —
        # two hand-overs at once, say — so the move is made only from where the
        # checks above saw it, and only once.
        next if @engagement.status == @to
        raise Error, "The engagement moved to #{@engagement.status} while this was being decided" if @engagement.status != from

        @engagement.update!(status: @to, status_history: Array(@engagement.status_history) + [history_entry(from)])
        moved = true
      end
      audit!(from) if moved
      @engagement
    end

    private

    def check_allowed!(from)
      raise Error, "Unknown status #{@to}" unless Engagement::STATUSES.include?(@to)
      return if ALLOWED.fetch(from, []).include?(@to)
      return if @force && @actor.is_a?(PlatformUser) && @reason && from != "CLOSED"

      raise Error, "An engagement can't move from #{from} to #{@to}"
    end

    # Onboarding is handed over only once the client has acknowledged how their
    # data is handled (A5) and planned who takes part (P1, P2) — Doc 07 §7, §9.1.
    def check_preconditions!
      return if @force

      case @to
      when "KEY_PERSON_DISCOVERY" then check_onboarding_handed_over!
      when "STAGE_1_PRICING" then check_ready_for_pricing!
      when "STAGE_1_ACTIVE" then check_price_accepted!
      when "CLOSED" then check_closed_by_mjadi!
      end
    end

    def check_onboarding_handed_over!
      raise Error, "The confidentiality acknowledgement is required" if @engagement.confidentiality_acknowledged_at.blank?
      raise Error, "Choose at least one department to take part" if Array(@engagement.planned_departments).empty?
    end

    # Stage 1 is priced after the key user's conversation with leadership (Doc 08
    # §13, Doc 17 §2.1), from how many people take part, so every planned count
    # must be a number by now. Other managers' conversations don't hold it up.
    def check_ready_for_pricing!
      own = @engagement.participants.find_by(source: "KEY_USER")
      unless own&.conversation_sessions&.last&.finished?
        raise Error, "The key user's conversation with leadership isn't finished yet"
      end
      raise Error, "Every department needs a number of people before pricing" if @engagement.planned_participant_count.nil?
    end

    # Stage 1 starts when the client's key user accepts the price (Doc 17
    # §10.3, Doc 22 E12); from then it is fixed (Decision Register B8).
    def check_price_accepted!
      raise Error, "The client hasn't accepted a Stage 1 quote yet" unless @engagement.accepted_stage1_quote
    end

    # An engagement whose price wasn't agreed may be closed by Mjadi, with a
    # reason — after a decline, say.
    def check_closed_by_mjadi!
      raise Error, "Only Mjadi can close an engagement, with a reason" unless @actor.is_a?(PlatformUser) && @reason
    end

    def history_entry(from)
      entry = { "from" => from, "to" => @to, "at" => Time.current.iso8601 }
      entry["reason"] = @reason if @reason
      entry["forced"] = true if @force
      if @actor
        entry["by_type"] = @actor.class.name
        entry["by_id"] = @actor.id
      end
      entry
    end

    def audit!(from)
      return unless @actor.is_a?(PlatformUser)

      PlatformAuditService.log!(
        platform_user: @actor,
        action: "engagement_status_changed",
        target: @engagement,
        metadata: { from: from, to: @to, reason: @reason, forced: @force }.compact,
        request: @request
      )
    end
  end
end
