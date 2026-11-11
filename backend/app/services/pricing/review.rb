# frozen_string_literal: true

module Pricing
  # What an administrator does with a proposed Stage 1 quote (Doc 17 §9.2,
  # Doc 05 §10, Doc 21 §26). Only a super admin may act (PricingPolicy); the
  # check is made here as well as by the controller, because the gate is
  # permanent (Doc 17 §0.1).
  #
  #   approve        issues the quote to the client. Below the margin floor it
  #                  needs an override with a structured reason (§8.3).
  #   adjust         a different price, with a structured reason: a new version
  #                  keeping the calculated lines plus an adjustment line.
  #   change_inputs  corrects the deep dives, locations or country and
  #                  recalculates — a new version.
  #   reject         sends it back with a note; the lead consultant is told.
  #   calculate      works the quote out now (an engagement already in pricing,
  #                  or a fresh quote after a decline or an expiry).
  #
  # Every action is kept as a quote event and in the platform audit log.
  class Review
    class Error < StandardError; end

    REVISABLE = %w[PROPOSED REJECTED DECLINED EXPIRED].freeze

    def initialize(actor:, request: nil)
      @actor = actor
      @request = request
      raise Error, "Only a super admin can decide prices" unless PricingPolicy::APPROVER_ROLE == actor.try(:role)
    end

    def approve(quote, floor_override: nil)
      quote.with_lock do
        check_pricing!(quote)
        raise Error, "Only a proposed quote can be approved" unless quote.proposed?

        override_floor!(quote, floor_override) if quote.below_floor
        issue!(quote)
      end
      audit!("stage1_quote_issued", quote, total: quote.total.to_s("F"), below_floor: quote.below_floor)
      Notifications.issued(quote)
      QuotePdfJob.perform_later(quote.id)
      quote
    end

    def adjust(quote, subtotal:, reason:, free_text: nil)
      new_quote = nil
      quote.engagement.with_lock do
        check_revisable!(quote)
        estimate = Stage1Estimate.from_h(quote.estimate, floor: quote.margin_floor_version)
        adjusted = estimate.adjusted(positive!(subtotal))
        override = EstimateOverride.new(kind: "ADJUST", original_total: estimate.calculated_subtotal,
                                        adjusted_total: adjusted.subtotal, structured_reason: reason,
                                        free_text: free_text.presence, actor: @actor)
        override.validate
        raise Error, override.errors.full_messages.to_sentence if (override.errors.attribute_names - [:quote]).any?

        supersede!(quote, "Adjusted by an administrator")
        new_quote = copy!(quote, adjusted)
        override.update!(quote: new_quote)
        new_quote.record!("adjusted", actor: @actor,
                                      detail: { from: estimate.calculated_subtotal.to_s("F"), to: adjusted.subtotal.to_s("F"),
                                                reason: reason, free_text: free_text.presence }.compact)
      end
      audit!("stage1_quote_adjusted", new_quote, reason: reason, subtotal: new_quote.subtotal.to_s("F"))
      ExplainStage1QuoteJob.perform_later(new_quote.id)
      new_quote
    end

    def change_inputs(quote, adjustments)
      adjustments = adjustments.to_h.stringify_keys.slice(*Stage1Inputs::ADJUSTABLE).compact_blank
      raise Error, "Say which input to change" if adjustments.empty?
      if adjustments.key?("deep_dives") && !adjustments["deep_dives"].to_s.match?(/\A\d+\z/)
        raise Error, "Deep dives must be a whole number"
      end

      check_revisable!(quote)
      result = ProposeStage1.call(quote.engagement, actor: @actor, reason: "Inputs changed by an administrator",
                                                    adjustments: adjustments)
      raise Error, result.error unless result.ok?

      audit!("stage1_quote_inputs_changed", result.quote, adjustments: adjustments)
      result.quote
    end

    def reject(quote, note:)
      raise Error, "Say why it is being sent back" if note.to_s.strip.empty?

      quote.with_lock do
        check_pricing!(quote)
        raise Error, "Only a proposed quote can be sent back" unless quote.proposed?

        quote.update!(status: "REJECTED", rejected_by: @actor, rejected_at: Time.current, rejection_note: note.strip)
        quote.record!("rejected", actor: @actor, detail: { note: note.strip })
      end
      audit!("stage1_quote_rejected", quote, note: note.strip)
      Notifications.rejected(quote)
      quote
    end

    def calculate(engagement)
      # Never moves the price under a client who is looking at it.
      raise Error, "This engagement's quote is with the client" if engagement.open_stage1_quote&.issued?

      result = ProposeStage1.call(engagement, actor: @actor, reason: "Calculated by an administrator")
      raise Error, result.error unless result.ok?

      audit!("stage1_quote_calculated", result.quote, version: result.quote.version) if result.fresh
      result.quote
    end

    private

    def check_pricing!(quote)
      raise Error, "The engagement isn't being priced" unless quote.engagement.status == "STAGE_1_PRICING"
    end

    # Only the newest version, and never one the client is looking at: a
    # change after issue would move the price under them.
    def check_revisable!(quote)
      check_pricing!(quote)
      raise Error, "A newer version of this quote exists" unless quote.engagement.latest_stage1_quote == quote
      raise Error, "This quote is with the client" if quote.issued?
      raise Error, "This quote can't be changed" unless REVISABLE.include?(quote.status)
    end

    def override_floor!(quote, floor_override)
      floor_override = (floor_override || {}).to_h.stringify_keys
      override = quote.estimate_overrides.new(kind: "FLOOR_OVERRIDE", original_total: quote.subtotal,
                                              adjusted_total: quote.subtotal, actor: @actor,
                                              structured_reason: floor_override["reason"],
                                              free_text: floor_override["free_text"].presence)
      unless override.save
        raise Error, "This quote is below the #{quote.margin_floor_version.percent}% margin floor: " \
                     "#{override.errors.full_messages.to_sentence.downcase}"
      end

      quote.record!("floor_overridden", actor: @actor,
                                        detail: { margin_percent: quote.margin_percent.to_s("F"),
                                                  floor_percent: quote.margin_floor_version.percent.to_s("F"),
                                                  reason: override.structured_reason, free_text: override.free_text }.compact)
    end

    def issue!(quote)
      days = quote.rate_card_version.stage1["validity_days"].to_i
      quote.update!(status: "ISSUED", approved_by: @actor, approved_at: Time.current, issued_at: Time.current,
                    valid_until: Time.zone.today + days)
      # The scope statement states the date it stands until, from the quote.
      quote.update!(client_scope: quote.client_scope.merge("validity" => ScopeTemplate.call(quote)["validity"]))
      quote.record!("issued", actor: @actor, detail: { valid_until: quote.valid_until.iso8601 })
    end

    def supersede!(quote, reason)
      return unless quote.open?

      quote.update!(status: "SUPERSEDED")
      quote.record!("superseded", actor: @actor, detail: { reason: reason })
    end

    def copy!(quote, estimate)
      quote.engagement.quotes.create!(
        company: quote.company, quote_stage: quote.quote_stage,
        version: Quote.next_version_for(quote.engagement, quote.quote_stage), parent_quote: quote, status: "PROPOSED",
        currency: quote.currency, rate_card_version: quote.rate_card_version,
        margin_floor_version: quote.margin_floor_version, inputs: quote.inputs, estimate: estimate.to_h,
        line_items: estimate.client_lines, subtotal: estimate.subtotal, tax_rate: estimate.tax_rate,
        tax_amount: estimate.tax_amount, total: estimate.total,
        additional_participant_rate: estimate.additional_participant_rate,
        participants_included: estimate.participants, deep_dives_included: estimate.deep_dives,
        internal: estimate.internal_h, margin_percent: estimate.margin_percent, below_floor: estimate.below_floor?,
        # The explanation quoted the old figures; the scope statement doesn't
        # mention the fee, so it still holds.
        admin_explanation: {}, client_scope: quote.client_scope, explanation_source: quote.explanation_source
      )
    end

    def positive!(subtotal)
      value = BigDecimal(subtotal.to_s)
      raise Error, "The price must be more than zero" unless value.positive?

      value
    rescue ArgumentError
      raise Error, "The price must be a number"
    end

    def audit!(action, quote, metadata)
      PlatformAuditService.log!(platform_user: @actor, action: action, target: quote,
                                metadata: metadata.merge(engagement_id: quote.engagement_id, version: quote.version),
                                request: @request)
    end
  end
end
