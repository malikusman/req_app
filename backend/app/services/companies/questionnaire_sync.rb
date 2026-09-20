# frozen_string_literal: true

module Companies
  # Folds questionnaire answers into company_profile + company_systems.
  #
  # The questionnaire is what the company says in their own words; company_profile
  # is the normalised form the rest of the platform reasons about (catalog fit,
  # report firmographics, agent context). This is the one place that translates.
  class QuestionnaireSync
    # Q01's option list. "Other" and anything unrecognised fall to "other" rather
    # than inventing a category.
    INDUSTRY_MAP = {
      "Retail & E-commerce" => "retail",
      "Manufacturing" => "manufacturing",
      "Construction & Engineering" => "other",
      "Healthcare & Medical" => "healthcare",
      "Real Estate" => "other",
      "Logistics & Transportation" => "logistics",
      "Hospitality & Food Service" => "other",
      "Professional Services" => "professional_services",
      "Financial Services & Insurance" => "finance",
      "Education" => "other",
      "IT & Software" => "technology",
      "Energy & Utilities" => "other",
      "Automotive" => "manufacturing",
      "Agriculture" => "other",
      "Media & Entertainment" => "other",
      "Government & Public Sector" => "other",
      "Other" => "other"
    }.freeze

    # Q03 asks in eight bands; company_profile speaks in five, and
    # Catalog::CompanyFitService matches on those five by string. Widening the
    # stored vocabulary would silently stop that matching, so the finer question
    # folds back into the coarser profile. The question is still worth asking at
    # eight — the answer is kept verbatim in the questionnaire either way.
    SIZE_MAP = {
      "1–10" => "1-10",
      "11–25" => "11-50",
      "26–50" => "11-50",
      "51–100" => "51-200",
      "101–250" => "51-200",
      "251–500" => "201-1000",
      "501–1,000" => "201-1000",
      "1,000+" => "1000+"
    }.freeze

    # Values that mean "we don't have one" rather than naming a system.
    NON_SYSTEMS = ["None", "Spreadsheets", "Mostly physical files", "A network shared drive",
                   "A shared email inbox", "Handled by an external accountant",
                   "Custom / in-house system", "Custom / in-house dashboards"].freeze

    def self.call(company:, answers:)
      new(company: company, answers: answers).call
    end

    def initialize(company:, answers:)
      @company = company
      @answers = (answers || {}).to_h.stringify_keys
    end

    def call
      country = @answers["q04_headquarters_country"].presence

      profile = {
        industry: mapped_industry,
        size_band: mapped_size,
        country: country,
        region: country,
        org_departments: string_list("q07_departments"),
        business_goals: string_list("q40_desired_outcomes")
      }.compact

      Companies::ProfileUpdater.call(
        company: @company,
        profile_params: profile,
        known_systems: known_systems
      )
      @company
    end

    private

    def mapped_industry
      raw = @answers["q01_primary_industry"].to_s
      return nil if raw.blank?

      INDUSTRY_MAP[raw] || "other"
    end

    def mapped_size
      raw = @answers["q03_employee_count"].to_s
      return nil if raw.blank?

      SIZE_MAP[raw] || raw
    end

    def string_list(key)
      Array(@answers[key]).map(&:to_s).reject(&:blank?)
    end

    # Q22 names a system per category; Q23 names the productivity tools in daily
    # use. Both are things the company actually runs, which is what company_systems
    # is for.
    def known_systems
      from_matrix = @answers["q22_business_systems"]
      names = from_matrix.is_a?(Hash) ? from_matrix.values.map(&:to_s) : []
      names += string_list("q23_productivity_tools")

      names.map(&:strip)
           .reject { |n| n.blank? || n.start_with?("Other") || NON_SYSTEMS.include?(n) }
           .uniq
    end
  end
end
