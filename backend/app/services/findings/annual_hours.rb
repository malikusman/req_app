# frozen_string_literal: true

module Findings
  # How many hours a year a piece of work takes, from how often and how long.
  #
  # This is the only place that arithmetic happens. The interview records what the
  # employee said — "every morning", "forty minutes to an hour" — as ranges with
  # units; no model ever produces an annual figure (Masood's Doc 05 §7.4: calculated
  # figures are computed by platform logic and passed in as grounded values).
  #
  # The basis is deliberately conservative, because a client who knows their own
  # business will check it, and understating survives that check where overstating
  # does not:
  #   - 48 working weeks a year (52 less leave and public holidays)
  #   - 5 working days a week, so 240 working days a year
  #   - 8 working hours a day, for durations given in days
  # The basis travels with every result so the report can say how it was worked out.
  class AnnualHours
    WORKING_WEEKS = 48
    WORKING_DAYS = WORKING_WEEKS * 5
    HOURS_PER_DAY = 8

    OCCURRENCES_PER_YEAR = {
      "per_day" => WORKING_DAYS,
      "per_week" => WORKING_WEEKS,
      "per_month" => 12,
      "per_quarter" => 4,
      "per_year" => 1
    }.freeze

    MINUTES = { "minutes" => 1, "hours" => 60, "days" => HOURS_PER_DAY * 60 }.freeze

    BASIS = {
      "method" => "occurrences per year x minutes per occurrence",
      "working_weeks" => WORKING_WEEKS,
      "working_days" => WORKING_DAYS,
      "hours_per_day" => HOURS_PER_DAY
    }.freeze

    Result = Struct.new(:min, :max, :basis, :reason, keyword_init: true) do
      def hours? = !min.nil?
    end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(frequency_min:, frequency_max:, frequency_unit:,
                   duration_min:, duration_max:, duration_unit:, effort_type: "unknown")
      @frequency_min = number(frequency_min)
      @frequency_max = number(frequency_max) || @frequency_min
      @frequency_unit = frequency_unit.to_s
      @duration_min = number(duration_min)
      @duration_max = number(duration_max) || @duration_min
      @duration_unit = duration_unit.to_s
      @effort_type = effort_type.to_s
    end

    def call
      # Waiting is not work. An approval that takes three days and two minutes of
      # effort is a delay problem, and counting the three days as capacity would be
      # the single easiest way to overstate a report.
      return empty("waiting is not effort") if @effort_type == "waiting"

      per_year = OCCURRENCES_PER_YEAR[@frequency_unit]
      minutes = MINUTES[@duration_unit]
      return empty("per-event work has no yearly volume yet") if @frequency_unit == "per_event"
      return empty("how often was not given as a number") if per_year.nil? || @frequency_min.nil?
      return empty("how long was not given as a number") if minutes.nil? || @duration_min.nil?

      low = @frequency_min * per_year * @duration_min * minutes / 60.0
      high = @frequency_max * per_year * @duration_max * minutes / 60.0
      low, high = [low, high].minmax

      Result.new(min: round_down(low), max: round_up(high), basis: BASIS, reason: nil)
    end

    private

    def empty(reason)
      Result.new(min: nil, max: nil, basis: BASIS, reason: reason)
    end

    def number(value)
      return nil if value.nil?

      float = Float(value)
      float.positive? ? float : nil
    rescue ArgumentError, TypeError
      nil
    end

    # Round the range outward to a step that does not imply precision a
    # conversation cannot give: "150–190 hours", never "157–186".
    def step(value)
      value < 20 ? 1 : (value < 200 ? 5 : 10)
    end

    def round_down(value)
      s = step(value)
      [(value / s).floor * s, value.positive? ? 1 : 0].max
    end

    def round_up(value)
      s = step(value)
      (value / s).ceil * s
    end
  end
end
