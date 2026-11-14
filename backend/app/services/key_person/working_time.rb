# frozen_string_literal: true

module KeyPerson
  # When a reminder may be sent: within working hours, on a working day, where
  # the company is (Doc 14 §8.1, §9). The headquarters country (onboarding O3)
  # is free text, so it is read loosely; anything not recognised is treated as
  # the UAE, Mjadi's home market.
  module WorkingTime
    FRI_SAT = [5, 6].freeze
    SAT_SUN = [6, 0].freeze

    # [pattern, time zone, weekend days (Date#wday)]
    COUNTRIES = [
      [/\b(saudi|ksa)\b|السعودية/i, "Asia/Riyadh", FRI_SAT],
      [/\bqatar\b|قطر/i, "Asia/Qatar", FRI_SAT],
      [/\boman\b|عُمان|سلطنة عمان/i, "Asia/Muscat", FRI_SAT],
      [/\bkuwait\b|الكويت/i, "Asia/Kuwait", FRI_SAT],
      [/\bbahrain\b|البحرين/i, "Asia/Bahrain", FRI_SAT],
      [/\begypt\b|مصر/i, "Africa/Cairo", FRI_SAT],
      [/\bjordan\b|الأردن/i, "Asia/Amman", FRI_SAT],
      [/\b(uae|u\.a\.e\.|united arab emirates|emirates|dubai|abu dhabi|sharjah)\b|الإمارات/i, "Asia/Dubai", SAT_SUN],
      [/\b(uk|united kingdom|england|britain|scotland|wales)\b/i, "Europe/London", SAT_SUN],
      [/\bpakistan\b/i, "Asia/Karachi", SAT_SUN],
      [/\bindia\b/i, "Asia/Kolkata", SAT_SUN]
    ].freeze
    DEFAULT = ["Asia/Dubai", SAT_SUN].freeze
    OPENS = 9
    CLOSES = 18

    module_function

    def zone_and_weekend(company)
      country = company.company_profile&.dig("country").to_s
      match = COUNTRIES.find { |pattern, _, _| country.match?(pattern) }
      match ? match.drop(1) : DEFAULT
    end

    def open?(company, at: Time.current)
      zone, weekend = zone_and_weekend(company)
      local = at.in_time_zone(zone)
      weekend.exclude?(local.wday) && local.hour >= OPENS && local.hour < CLOSES
    end

    # Whole working days from one moment to another, in the company's calendar.
    def working_days_between(from, to, company)
      return 0 if from.nil? || to <= from

      zone, weekend = zone_and_weekend(company)
      start = from.in_time_zone(zone).to_date
      finish = to.in_time_zone(zone).to_date
      ((start + 1)..finish).count { |day| weekend.exclude?(day.wday) }
    end
  end
end
