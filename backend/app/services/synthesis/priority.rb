# frozen_string_literal: true

module Synthesis
  # The platform's priority for an opportunity — a documented, versioned rule
  # over the evidence, kept apart from management importance (Doc 10 §12.5,
  # §15; Doc 08 §17). Leadership's view enters only through the evidence: a
  # concern staff evidence supports raises priority, as Doc 10 §15 says. What
  # leadership said mattered is never read here directly.
  #
  # PRI.v1, points:
  #   de-duplicated capacity behind it   ≥ 400 h/yr: 2   ≥ 150: 1
  #   breadth                            cross-department or company-wide: 2
  #                                      department or process: 1
  #   confidence                         HIGH: 1   LOW: −1
  #   leadership concern borne out       SUPPORTED: 1
  #   HIGH at 4 or more, MEDIUM at 2 or 3, LOW below. Deferred or not
  #   recommended is always LOW.
  # Pending the client's own rule (open question for the client).
  module Priority
    RULE_VERSION = "PRI.v1"
    BROAD = %w[CROSS_DEPARTMENT COMPANY_WIDE].freeze
    MIDDLE = %w[DEPARTMENT PROCESS].freeze

    module_function

    def call(level:, confidence:, next_action:, capacity_max:, leadership_support:)
      if %w[DEFER NOT_RECOMMENDED].include?(next_action)
        return ["LOW", "Recommended to #{next_action == 'DEFER' ? 'defer' : 'leave for now'}."]
      end

      points = 0
      reasons = []
      if capacity_max.to_f >= 400
        points += 2
        reasons << "substantial de-duplicated time behind it"
      elsif capacity_max.to_f >= 150
        points += 1
        reasons << "meaningful de-duplicated time behind it"
      end
      if BROAD.include?(level)
        points += 2
        reasons << "spans departments"
      elsif MIDDLE.include?(level)
        points += 1
        reasons << "covers a whole process or department"
      end
      if confidence == "HIGH"
        points += 1
        reasons << "well evidenced"
      elsif confidence == "LOW"
        points -= 1
        reasons << "evidence still thin"
      end
      if leadership_support == "SUPPORTED"
        points += 1
        reasons << "a leadership concern staff evidence bears out"
      end

      level_name = if points >= 4 then "HIGH"
                   elsif points >= 2 then "MEDIUM"
                   else "LOW"
                   end
      [level_name, reasons.empty? ? "Little evidence of scale yet." : "#{reasons.join(', ').upcase_first}."]
    end
  end
end
