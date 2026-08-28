# frozen_string_literal: true

module Discovery
  # Caps on consultant follow-up questions, separate from the interview's own
  # limits. Resolution is the same as Discovery::ContextBuilder — company setting ->
  # ENV -> code default — and for the same reason these keys are absent from
  # Company::DEFAULT_SETTINGS: merged_settings folds the defaults in, so a key
  # listed there would always look operator-set and ENV could never win.
  #
  # Two levels because they protect different things. The per-requirement cap stops
  # one unsatisfiable need generating questions forever. The per-package cap protects
  # the EMPLOYEE: three requirements each spending a budget of three is nine
  # questions to one person, more than the entire discovery interview is allowed.
  class FollowupLimits
    DEFAULTS = {
      "consultant_followup_max_per_requirement" => {
        env: "CONSULTANT_FOLLOWUP_MAX_PER_REQUIREMENT", default: 3
      },
      "consultant_followup_max_per_package" => {
        env: "CONSULTANT_FOLLOWUP_MAX_PER_PACKAGE", default: 6
      }
    }.freeze

    def self.for(company)
      overrides = company.settings.is_a?(Hash) ? company.settings : {}

      DEFAULTS.each_with_object({}) do |(key, spec), out|
        raw = overrides[key].presence || ENV[spec[:env]].presence
        out[key.delete_prefix("consultant_followup_").to_sym] = raw ? raw.to_i : spec[:default]
      end
    end

    def self.max_per_requirement(company)
      self.for(company)[:max_per_requirement]
    end

    def self.max_per_package(company)
      self.for(company)[:max_per_package]
    end

    # Questions already put to this employee for this package, across every
    # requirement plus the agent's own drafted follow-ups.
    def self.package_questions_asked(package)
      package.discovery_followup_questions.where(status: %w[sent answered]).count
    end

    def self.package_budget_remaining(package)
      [max_per_package(package.company) - package_questions_asked(package), 0].max
    end
  end
end
