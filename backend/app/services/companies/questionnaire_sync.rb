# frozen_string_literal: true

module Companies
  # Syncs questionnaire answers into company_profile + company_systems.
  class QuestionnaireSync
    INDUSTRY_MAP = {
      "Retail & E-commerce" => "retail",
      "Manufacturing" => "manufacturing",
      "Construction & Engineering" => "other",
      "Healthcare & Medical" => "healthcare",
      "Real Estate" => "other",
      "Logistics & Transportation" => "logistics",
      "Hospitality & Food Service" => "other",
      "Professional Services (Legal/Consulting/Accounting)" => "professional_services",
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

    SIZE_MAP = {
      "1–10" => "1-10",
      "1-10" => "1-10",
      "11–50" => "11-50",
      "11-50" => "11-50",
      "51–200" => "51-200",
      "51-200" => "51-200",
      "201–500" => "201-500",
      "201-500" => "201-500",
      "500+" => "500+"
    }.freeze

    REVENUE_MAP = {
      "Prefer not to say" => nil,
      "<$500K" => "under_500k",
      "$500K–$2M" => "500k_2m",
      "$2M–$10M" => "2m_10m",
      "$10M–$50M" => "10m_50m",
      "$50M+" => "50m_plus"
    }.freeze

    SYSTEM_KEYS = %w[erp_system crm_system accounting_software hr_software].freeze

    def self.call(company:, answers:)
      new(company: company, answers: answers).call
    end

    def initialize(company:, answers:)
      @company = company
      @answers = (answers || {}).to_h.stringify_keys
    end

    def call
      profile = {
        industry: mapped_industry,
        size_band: mapped_size,
        country: @answers["company_location"].presence,
        region: @answers["company_location"].presence,
        annual_revenue_band: mapped_revenue,
        org_departments: Array(@answers["departments_present"]).map(&:to_s).reject(&:blank?),
        business_goals: Array(@answers["primary_goals"]).map(&:to_s).reject(&:blank?)
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
      raw = @answers["company_industry"].to_s
      return nil if raw.blank?

      INDUSTRY_MAP[raw] || "other"
    end

    def mapped_size
      raw = @answers["company_size"].to_s
      return nil if raw.blank?

      SIZE_MAP[raw] || raw
    end

    def mapped_revenue
      raw = @answers["annual_revenue"].to_s
      return nil if raw.blank?

      REVENUE_MAP.fetch(raw, raw.parameterize.underscore)
    end

    def known_systems
      names = []
      SYSTEM_KEYS.each do |key|
        value = @answers[key].to_s.strip
        next if value.blank? || value == "None"

        names << value
      end
      Array(@answers["communication_tools"]).each do |tool|
        t = tool.to_s.strip
        next if t.blank? || t == "Other"

        names << t
      end
      names.uniq
    end
  end
end
