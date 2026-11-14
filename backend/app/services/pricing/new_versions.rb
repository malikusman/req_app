# frozen_string_literal: true

module Pricing
  # An administrator setting new Stage 1 rates or a new margin floor (Doc 17
  # §7, §8.3; Doc 05 §10). Neither is ever edited: each change is a new version,
  # in effect from now, with who made it and why. A floor that can be lowered
  # without trace is not a control, so a reason is required for both.
  #
  # Quotes already made keep the version they were made with; the next
  # calculation uses the new one.
  class NewVersions
    class Error < StandardError; end

    TEXT_KEYS = %w[payment_terms_text terms_reference_text].freeze

    def initialize(actor:, request: nil)
      raise Error, "Only a super admin can change rates or the margin floor" unless PricingPolicy::APPROVER_ROLE == actor.try(:role)

      @actor = actor
      @request = request
    end

    # params: stage1 (the formula's values, as the form sends them),
    # consultant_internal_cost, consultant_charge_rate, currency, placeholder, reason.
    def rate_card(params)
      params = params.to_h.deep_stringify_keys
      current = RateCardVersion.current
      reason = params["reason"].to_s.strip
      raise Error, "Say why the rates are changing" if reason.empty?

      record = RateCardVersion.new(
        version: RateCardVersion.next_version, effective_from: Time.current,
        currency: params["currency"].presence || current&.currency || "AED",
        rates: rates(current, params), stage1: stage1(params["stage1"] || {}),
        placeholder: ActiveModel::Type::Boolean.new.cast(params["placeholder"]) || false,
        reason: reason, changed_by: @actor
      )
      raise Error, record.errors.full_messages.to_sentence unless record.save

      audit!("rate_card_version_created", record, version: record.version, from_version: current&.version,
                                                  placeholder: record.placeholder, reason: reason)
      record
    end

    # percent: the new floor as a percentage, e.g. 60.
    def margin_floor(percent:, reason:)
      reason = reason.to_s.strip
      raise Error, "Say why the floor is changing" if reason.empty?

      current = MarginFloorVersion.current
      value = BigDecimal(percent.to_s) / 100
      record = MarginFloorVersion.new(version: MarginFloorVersion.next_version, value: value,
                                      effective_from: Time.current, reason: reason, changed_by: @actor)
      raise Error, "The floor must be between 0 and 100%" unless record.save

      audit!("margin_floor_changed", record, from: current&.percent&.to_s("F"), to: record.percent.to_s("F"),
                                             reason: reason)
      record
    rescue ArgumentError
      raise Error, "The floor must be a number"
    end

    private

    # Only the consultant's Mjadi-team rates are set here; the other skills and
    # sources, used from Stage 2, are carried over unchanged.
    def rates(current, params)
      rates = (current&.rates || Defaults::RATES_V1).deep_dup
      rates["consultant"] ||= {}
      rates["consultant"]["mjadi_team"] = {
        "internal_cost" => number(params["consultant_internal_cost"]),
        "charge_rate" => number(params["consultant_charge_rate"])
      }.compact
      rates
    end

    # The formula's values only, as numbers; anything else the form sends is
    # dropped.
    def stage1(input)
      out = {}
      RateCardVersion::STAGE1_NUMBERS.each do |path|
        keys = path.split(".")
        value = number(input.dig(*keys))
        next if value.nil?

        keys[0..-2].inject(out) { |h, k| h[k] ||= {} }[keys.last] = value
      end
      out["tax_rates"] = Array(input["tax_rates"]).each_with_object({}) do |(country, rate), h|
        code = Stage1Inputs.country_code(country)
        h[code.to_s.upcase] = number(rate) if code.present? && number(rate)
      end
      TEXT_KEYS.each { |k| out[k] = input[k].to_s.strip }
      out
    end

    def number(value)
      return nil if value.nil? || value.to_s.strip.empty?

      decimal = BigDecimal(value.to_s.strip)
      decimal.frac.zero? ? decimal.to_i : decimal.to_f
    rescue ArgumentError
      nil
    end

    def audit!(action, target, metadata)
      PlatformAuditService.log!(platform_user: @actor, action: action, target: target, metadata: metadata,
                                request: @request)
    end
  end
end
