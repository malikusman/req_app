# frozen_string_literal: true

module Pricing
  # The Stage 1 fee, worked out in code from the engagement's inputs and the
  # rate card (Doc 17 §2.3, §16: every figure is computed by the platform; the
  # model only explains). The same inputs and rate card always give the same
  # result.
  #
  # The fee has four parts — base, per participant, per deep dive and a
  # complexity adjustment for extra languages, locations and departments — plus
  # an additional-participant rate stated up front. Each part is rounded to a
  # whole unit of currency and the subtotal is their sum, so the client can add
  # the lines up; tax is the subtotal times the country's rate, to the cent.
  #
  # Alongside the fee it works out what Mjadi expects to spend: consultant hours
  # at internal cost, AI usage, an allocation of platform running cost and
  # licences — the fully loaded cost the margin is measured against, never
  # labour alone (§8.2). Margin and cost are INTERNAL_COMMERCIAL.
  class Stage1Calculator
    class MissingRate < StandardError; end
    class NotEstimable < StandardError; end

    WHOLE = 0
    CENTS = 2

    def self.call(inputs:, rate_card:, floor:, comparables: [])
      new(inputs: inputs, rate_card: rate_card, floor: floor, comparables: comparables).call
    end

    def initialize(inputs:, rate_card:, floor:, comparables:)
      @inputs = inputs
      @rate_card = rate_card
      @floor = floor
      @comparables = comparables
    end

    def call
      check_rates!
      raise NotEstimable, "Every department needs a number of people before Stage 1 can be priced" unless participants.positive?

      lines = fee_lines
      Stage1Estimate.new(
        lines: lines, tax_rate: tax_rate, cost: cost, hours: hours, floor: @floor,
        additional_participant_rate: money(rate("additional_participant_rate"), WHOLE),
        participants: participants, deep_dives: deep_dives, risk_signals: risk_signals,
        consultant_internal_cost: number(@rate_card.consultant_internal_cost)
      )
    end

    private

    def participants = @inputs.participants.to_i

    def deep_dives
      return @inputs.deep_dives.to_i if @inputs.deep_dives

      participants.clamp(rate("deep_dives.min").to_i, rate("deep_dives.max").to_i)
    end

    def extra_languages = [@inputs.languages.size - 1, 0].max
    def extra_locations = [@inputs.locations - 1, 0].max
    def departments_over = [@inputs.departments.size - rate("complexity.departments_threshold").to_i, 0].max

    def fee_lines
      lines = [
        line("base", "Base engagement", 1, rate("base_fee"),
             "Onboarding, the conversation with leadership, analysis across departments, the Diagnostic Report " \
             "and consultant review"),
        line("participants", "Team conversations", participants, rate("per_participant_fee"),
             "One discovery conversation for each person taking part"),
        line("deep_dives", "Detailed sessions", deep_dives, rate("per_deep_dive_fee"),
             "One task looked at properly in each, with its plan prepared and checked for completeness")
      ]
      complexity = complexity_amount
      if complexity.positive?
        lines << { "key" => "complexity", "label" => "Languages, locations and departments", "quantity" => 1,
                   "unit_amount" => complexity, "amount" => complexity, "detail" => complexity_detail }
      end
      lines
    end

    def line(key, label, quantity, unit, detail)
      unit = money(unit, WHOLE)
      { "key" => key, "label" => label, "quantity" => quantity, "unit_amount" => unit,
        "amount" => money(unit * quantity, WHOLE), "detail" => detail }
    end

    def complexity_amount
      money((extra_languages * rate("complexity.per_extra_language")) +
            (extra_locations * rate("complexity.per_extra_location")) +
            (departments_over * rate("complexity.per_department_over_threshold")), WHOLE)
    end

    def complexity_detail
      parts = []
      parts << "#{@inputs.languages.size} working languages" if extra_languages.positive?
      parts << "#{@inputs.locations} locations" if extra_locations.positive?
      parts << "#{@inputs.departments.size} departments" if departments_over.positive?
      parts.join(", ")
    end

    # Where the consultant's time goes, so the administrator can see what the
    # fee has to sustain (P24: effort_basis).
    def hours
      @hours ||= {
        "oversight_and_report" => rate("hours.base"),
        "team_conversations" => participants * rate("hours.per_participant"),
        "deep_dives" => deep_dives * rate("hours.per_deep_dive"),
        "leadership_conversations" => @inputs.key_persons * rate("hours.per_key_person"),
        "languages" => extra_languages * rate("hours.per_extra_language"),
        "locations" => extra_locations * rate("hours.per_extra_location")
      }.transform_values { |h| h.round(2) }.reject { |_k, h| h.zero? }
    end

    def cost
      @cost ||= begin
        consultant = hours.values.sum * number(@rate_card.consultant_internal_cost)
        ai = (participants * rate("ai_cost.per_participant")) + (deep_dives * rate("ai_cost.per_deep_dive")) +
             (@inputs.key_persons * rate("ai_cost.per_key_person"))
        parts = { "consultant_time" => consultant, "ai_usage" => ai, "platform_allocation" => rate("platform_allocation"),
                  "licences" => rate("licences") }.transform_values { |v| money(v, CENTS) }
        parts.merge("total" => parts.values.sum)
      end
    end

    def tax_rate
      rates = @rate_card.stage1["tax_rates"] || {}
      country = @inputs.country.presence || "AE"
      raise MissingRate, "The rate card has no tax rate for #{country}" unless rates.key?(country)

      number(rates[country])
    end

    def risk_signals
      signals = []
      signals << signal("NO_COMPARABLES", "No completed engagements of a similar size to compare with yet") if @comparables.empty?
      signals << signal("SEVERAL_LANGUAGES", "Work runs in #{@inputs.languages.size} languages, which can add review time") if extra_languages.positive?
      signals << signal("SEVERAL_LOCATIONS", "#{@inputs.locations} locations to coordinate") if extra_locations.positive?
      unnamed = participants - @inputs.named_participants
      signals << signal("PARTICIPANTS_NOT_NAMED", "#{unnamed} of #{participants} participants are not named yet, so scheduling effort is unknown") if unnamed.positive?
      thin = @inputs.departments.select { |d| d["count"] == 1 }.map { |d| d["name"] }
      signals << signal("THIN_DEPARTMENT", "Only one person from #{thin.to_sentence} for a team of #{participants}") if thin.any? && participants >= 6
      signals << signal("PLACEHOLDER_RATES", "The rate card's values are placeholders until they are agreed") if @rate_card.placeholder
      signals
    end

    def signal(code, text) = { "code" => code, "text" => text }

    def check_rates!
      missing = RateCardVersion::STAGE1_NUMBERS.reject { |path| @rate_card.stage1_value(path).is_a?(Numeric) }
      missing << "consultant internal cost" unless @rate_card.consultant_internal_cost.is_a?(Numeric)
      raise MissingRate, "The rate card has no value for #{missing.join(', ')}" if missing.any?
    end

    def rate(path) = number(@rate_card.stage1_value(path))

    def number(value) = BigDecimal(value.to_s)

    def money(value, places) = BigDecimal(value.to_s).round(places, BigDecimal::ROUND_HALF_UP)
  end
end
