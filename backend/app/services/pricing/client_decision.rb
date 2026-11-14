# frozen_string_literal: true

module Pricing
  # The key user accepting or declining the issued Stage 1 quote in the portal
  # (Doc 17 §10.3, Doc 22 E12). Acceptance is recorded with who and when, and
  # moves the engagement to STAGE_1_ACTIVE in the same transaction — from then
  # the price is fixed (Decision Register B8) and the team can be invited
  # (Doc 14 §4.1). A decline is recorded with the reason, if they give one, and
  # Mjadi is told.
  class ClientDecision
    class Error < StandardError
      attr_reader :status

      def initialize(message, status = :unprocessable_entity)
        super(message)
        @status = status
      end
    end

    def initialize(quote, company_user)
      @quote = quote
      @user = company_user
    end

    def accept(acknowledged:)
      raise Error, "Confirm that you've read what's included and the additional-participant rate" unless acknowledged

      @quote.with_lock do
        check!
        @quote.update!(status: "ACCEPTED", accepted_by: @user, accepted_at: Time.current)
        @quote.record!("accepted", actor: @user)
        Engagements::Transition.call(engagement: @quote.engagement, to: "STAGE_1_ACTIVE", actor: @user,
                                     reason: "Stage 1 quote v#{@quote.version} accepted")
      end
      Notifications.decided(@quote)
      @quote
    end

    def decline(reason: nil)
      @quote.with_lock do
        check!
        @quote.update!(status: "DECLINED", declined_by: @user, declined_at: Time.current,
                       decline_reason: reason.to_s.strip.presence)
        @quote.record!("declined", actor: @user, detail: { reason: @quote.decline_reason }.compact)
      end
      Notifications.decided(@quote)
      @quote
    end

    private

    def check!
      raise Error.new("Only #{key_user_name} can accept or decline the proposal", :forbidden) unless key_user?
      raise Error.new("This proposal is no longer open", :conflict) unless @quote.issued? && @quote.engagement.status == "STAGE_1_PRICING"
      raise Error.new("This proposal has expired; your consultant will send a fresh one", :conflict) if @quote.past_validity?
    end

    def key_user? = @quote.engagement.key_user_id == @user.id
    def key_user_name = @quote.engagement.key_user&.name || "your key user"
  end
end
