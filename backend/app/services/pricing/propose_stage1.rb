# frozen_string_literal: true

module Pricing
  # Works out a Stage 1 quote for an engagement in STAGE_1_PRICING and puts it
  # in front of the administrators (Doc 17 §1, §2; AI proposes, the
  # administrator approves, §0.1).
  #
  # Runs when the engagement reaches pricing, when Mjadi changes the plan or the
  # languages before the client has accepted, and when an administrator
  # corrects an input or asks for a fresh quote after a decline or expiry. The
  # open quote, if any, is superseded by the new version (Doc 06 §1.2); a quote
  # the administrator already corrected keeps those corrections. Run again with
  # nothing changed, it returns the open quote rather than making another.
  #
  # A rate card missing a value stops it and tells the administrators (Doc 17
  # §17); so does a plan that isn't a number yet. Nothing is guessed.
  class ProposeStage1
    Result = Struct.new(:quote, :error, :fresh, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(engagement, actor: nil, reason: nil, adjustments: {})
      new(engagement, actor: actor, reason: reason, adjustments: adjustments).call
    end

    # Changes to what the fee is calculated from, made by Mjadi while the
    # engagement is being priced.
    def self.reprice_if_pricing(engagement, actor:, reason:)
      return unless engagement.status == "STAGE_1_PRICING"

      call(engagement, actor: actor, reason: reason)
    end

    def initialize(engagement, actor:, reason:, adjustments:)
      @engagement = engagement
      @actor = actor
      @reason = reason
      @adjustments = adjustments.to_h.stringify_keys
    end

    def call
      result = nil
      @engagement.with_lock do
        result = propose
      end
      announce(result)
      result
    rescue Stage1Calculator::MissingRate, Stage1Calculator::NotEstimable => e
      blocked(e)
    end

    private

    def propose
      return Result.new(error: "The engagement isn't being priced") unless @engagement.status == "STAGE_1_PRICING"
      return Result.new(error: "The client has already accepted a Stage 1 quote") if @engagement.accepted_stage1_quote

      latest = @engagement.latest_stage1_quote
      inputs = Stage1Inputs.from(@engagement, carried_corrections(latest).merge(@adjustments))
      rate_card = RateCardVersion.current
      floor = MarginFloorVersion.current
      raise Stage1Calculator::MissingRate, "There is no rate card or margin floor in effect" unless rate_card && floor

      open = @engagement.open_stage1_quote
      return Result.new(quote: open) if open && unchanged?(open, inputs, rate_card, floor)

      estimate = Stage1Calculator.call(inputs: inputs, rate_card: rate_card, floor: floor,
                                       comparables: Comparables.for(@engagement, inputs.participants))
      supersede!(open)
      Result.new(quote: create_quote!(latest, inputs, estimate, rate_card, floor), fresh: true)
    end

    # What an administrator corrected on the last version stays corrected.
    def carried_corrections(latest)
      return {} unless latest

      sources = latest.inputs.fetch("sources", {})
      Stage1Inputs::ADJUSTABLE.select { |key| sources[key] == "ADMINISTRATOR" }.index_with { |key| latest.inputs[key] }
    end

    def unchanged?(quote, inputs, rate_card, floor)
      @adjustments.empty? && quote.inputs == JSON.parse(inputs.to_h.to_json) &&
        quote.rate_card_version_id == rate_card.id && quote.margin_floor_version_id == floor.id
    end

    def supersede!(quote)
      return unless quote

      quote.update!(status: "SUPERSEDED")
      quote.record!("superseded", actor: @actor, detail: { reason: @reason }.compact)
    end

    def create_quote!(latest, inputs, estimate, rate_card, floor)
      quote = @engagement.quotes.create!(
        company: @engagement.company, quote_stage: "STAGE_1", version: Quote.next_version_for(@engagement, "STAGE_1"),
        parent_quote: latest, status: "PROPOSED", currency: rate_card.currency,
        rate_card_version: rate_card, margin_floor_version: floor,
        inputs: inputs.to_h, estimate: estimate.to_h, line_items: estimate.client_lines,
        subtotal: estimate.subtotal, tax_rate: estimate.tax_rate, tax_amount: estimate.tax_amount, total: estimate.total,
        additional_participant_rate: estimate.additional_participant_rate,
        participants_included: estimate.participants, deep_dives_included: estimate.deep_dives,
        internal: estimate.internal_h, margin_percent: estimate.margin_percent, below_floor: estimate.below_floor?
      )
      quote.update!(client_scope: ScopeTemplate.call(quote), explanation_source: "TEMPLATE")
      quote.record!(@adjustments.any? ? "inputs_changed" : "proposed", actor: @actor,
                    detail: { reason: @reason, adjustments: @adjustments.presence }.compact)
      quote
    end

    # Each new version is explained by P24. One from the platform, not from the
    # administrator's own hand, waits for them (Doc 21 §42).
    def announce(result)
      return unless result.fresh

      ExplainStage1QuoteJob.perform_later(result.quote.id)
      return if @actor.is_a?(PlatformUser)

      PricingMailer.quote_awaiting_approval(result.quote).deliver_later
    end

    def blocked(error)
      Rails.logger.warn("[Pricing::ProposeStage1] engagement #{@engagement.id}: #{error.message}")
      PricingMailer.pricing_blocked(@engagement, error.message).deliver_later if error.is_a?(Stage1Calculator::MissingRate)
      Result.new(error: error.message)
    end
  end
end
