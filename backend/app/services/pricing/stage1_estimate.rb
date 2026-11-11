# frozen_string_literal: true

module Pricing
  # A calculated Stage 1 fee (Doc 06 §10 Stage1Estimate): the lines the client
  # will see, tax, the additional-participant rate, and — internal only — the
  # hours, fully loaded cost and margin against the floor (Doc 17 §8).
  #
  # An administrator's price change keeps the calculated lines and adds an
  # "Adjustment" line for the difference, so the derivation still shows what
  # the platform proposed (§9.1: an unexplained number cannot be reviewed).
  class Stage1Estimate
    attr_reader :lines, :tax_rate, :cost, :hours, :floor, :additional_participant_rate, :participants, :deep_dives,
                :risk_signals, :consultant_internal_cost

    # rubocop:disable Metrics/ParameterLists
    def initialize(lines:, tax_rate:, cost:, hours:, floor:, additional_participant_rate:, participants:, deep_dives:,
                   risk_signals:, consultant_internal_cost:)
      @lines = lines
      @tax_rate = tax_rate
      @cost = cost
      @hours = hours
      @floor = floor
      @additional_participant_rate = additional_participant_rate
      @participants = participants
      @deep_dives = deep_dives
      @risk_signals = risk_signals
      @consultant_internal_cost = consultant_internal_cost
    end
    # rubocop:enable Metrics/ParameterLists

    def subtotal = lines.sum { |l| l["amount"] }
    def tax_amount = (subtotal * tax_rate).round(2, BigDecimal::ROUND_HALF_UP)
    def total = subtotal + tax_amount
    def total_hours = hours.values.sum

    def margin_percent
      raise Stage1Calculator::NotEstimable, "A Stage 1 fee must be more than zero" unless subtotal.positive?

      ((subtotal - cost["total"]) / subtotal * 100).round(2, BigDecimal::ROUND_HALF_UP)
    end

    def floor_percent = floor.percent
    def below_floor? = margin_percent < floor_percent

    # HIGH with nothing to flag; no comparables caps it at MEDIUM (P24 §9); three
    # or more concerns make it LOW. Placeholder rates are flagged but say
    # nothing about this engagement.
    def confidence
      concerns = risk_signals.reject { |s| s["code"] == "PLACEHOLDER_RATES" }
      return "LOW" if concerns.size >= 3
      return "MEDIUM" if concerns.any?

      "HIGH"
    end

    def calculated_subtotal = lines.reject { |l| l["key"] == "adjustment" }.sum { |l| l["amount"] }

    def adjusted(new_subtotal)
      new_subtotal = BigDecimal(new_subtotal.to_s).round(0, BigDecimal::ROUND_HALF_UP)
      difference = new_subtotal - calculated_subtotal
      kept = lines.reject { |l| l["key"] == "adjustment" }
      unless difference.zero?
        kept += [{ "key" => "adjustment", "label" => "Adjustment", "quantity" => 1, "unit_amount" => difference,
                   "amount" => difference, "detail" => "" }]
      end
      self.class.new(lines: kept, tax_rate: tax_rate, cost: cost, hours: hours, floor: floor,
                     additional_participant_rate: additional_participant_rate, participants: participants,
                     deep_dives: deep_dives, risk_signals: risk_signals, consultant_internal_cost: consultant_internal_cost)
    end

    # Rebuilds an estimate stored on a quote, to adjust it.
    def self.from_h(hash, floor:)
      hash = hash.deep_stringify_keys
      decimal = ->(v) { BigDecimal(v.to_s) }
      new(
        lines: hash["lines"].map { |l| l.merge("unit_amount" => decimal.(l["unit_amount"]), "amount" => decimal.(l["amount"])) },
        tax_rate: decimal.(hash["tax_rate"]), hours: hash["hours"].transform_values(&decimal),
        cost: hash["cost"].transform_values(&decimal), floor: floor,
        additional_participant_rate: decimal.(hash["additional_participant_rate"]),
        participants: hash["participants"], deep_dives: hash["deep_dives"], risk_signals: hash["risk_signals"],
        consultant_internal_cost: decimal.(hash["consultant_internal_cost"])
      )
    end

    # Everything, as stored on the quote's `estimate` (INTERNAL_COMMERCIAL).
    def to_h
      {
        "lines" => lines.map { |l| l.merge("unit_amount" => l["unit_amount"].to_s("F"), "amount" => l["amount"].to_s("F")) },
        "subtotal" => subtotal.to_s("F"), "tax_rate" => tax_rate.to_s("F"), "tax_amount" => tax_amount.to_s("F"),
        "total" => total.to_s("F"), "additional_participant_rate" => additional_participant_rate.to_s("F"),
        "participants" => participants, "deep_dives" => deep_dives,
        "hours" => hours.transform_values { |h| h.to_s("F") }, "total_hours" => total_hours.to_s("F"),
        "consultant_internal_cost" => consultant_internal_cost.to_s("F"),
        "cost" => cost.transform_values { |c| c.to_s("F") },
        "margin_percent" => margin_percent.to_s("F"), "floor_percent" => floor_percent.to_s("F"),
        "below_floor" => below_floor?, "confidence" => confidence, "risk_signals" => risk_signals,
        "delivery_mix" => { "consultant" => { "mjadi_team" => { "hours" => total_hours.to_s("F") } } }
      }
    end

    # The parts a quote keeps in `internal`: what Mjadi expects to spend and earn.
    def internal_h
      to_h.slice("hours", "total_hours", "cost", "margin_percent", "floor_percent", "below_floor", "delivery_mix")
    end

    # The lines as the client sees them.
    def client_lines
      lines.map { |l| { "key" => l["key"], "label" => l["label"], "quantity" => l["quantity"],
                        "unit_amount" => l["unit_amount"].to_s("F"), "amount" => l["amount"].to_s("F"),
                        "detail" => l["detail"] } }
    end
  end
end
