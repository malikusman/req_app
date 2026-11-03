# frozen_string_literal: true

module Companies
  # The company onboarding form (Doc 07 §6–7): eleven factual fields, participant
  # planning and the key user's language. This is the authority on what may be
  # stored and which values are allowed; question text lives in the frontend
  # (frontend/src/lib/onboardingFields.ts), and a spec keeps the two in step.
  #
  # Nothing here asks about goals, pain points, budget, revenue, timelines or
  # readiness — those belong to the key-person conversation (Doc 07 §2). The old
  # 43-question questionnaire's keys are not on the whitelist, so they cannot be
  # stored.
  #
  # Every field accepts "Not sure" (Doc 07 §6), stored as the literal answer and
  # recorded as unknown in the profile's provenance.
  class OnboardingFields
    NOT_SURE = "Not sure"
    OTHER = "Other"

    # Option label → company_profile industry code. The codes are what the
    # catalogue fit and the report read.
    INDUSTRIES = {
      "Wholesale & distribution" => "wholesale_distribution",
      "Retail & e-commerce" => "retail",
      "Manufacturing" => "manufacturing",
      "Logistics & transport" => "logistics",
      "Construction & engineering" => "construction",
      "Real estate" => "real_estate",
      "Professional services" => "professional_services",
      "Financial services & insurance" => "finance",
      "Healthcare" => "healthcare",
      "Hospitality & food" => "hospitality",
      "Education" => "education",
      "Technology & software" => "technology",
      "Energy & utilities" => "energy",
      "Automotive" => "automotive",
      "Media & marketing" => "media",
      "Government & public sector" => "government",
      "Agriculture & food production" => "agriculture"
    }.freeze

    # Company::SIZE_BANDS, as shown.
    HEADCOUNTS = {
      "1–10" => "1-10", "11–50" => "11-50", "51–200" => "51-200",
      "201–500" => "201-500", "501–1,000" => "501-1000", "1,000+" => "1000+"
    }.freeze

    # Doc 07 §6 O4 together with Doc 06 / P01's SERVICES, as Doc 06 codes.
    BUSINESS_MODELS = {
      "B2B" => "B2B", "B2C" => "B2C", "B2B2C" => "B2B2C", "Wholesale" => "WHOLESALE", "Retail" => "RETAIL",
      "Distribution" => "DISTRIBUTION", "Manufacturing" => "MANUFACTURING", "Services" => "SERVICES",
      "Project-based" => "PROJECT", "Marketplace" => "MARKETPLACE", "Subscription" => "SUBSCRIPTION"
    }.freeze

    # Doc 07 §6 O7, with P01's online store, as P01 codes.
    CHANNELS = {
      "Email" => "EMAIL", "Phone" => "PHONE", "WhatsApp" => "WHATSAPP", "Website" => "WEBSITE",
      "Online store" => "ONLINE_STORE", "Social media" => "SOCIAL_MEDIA", "Marketplaces" => "MARKETPLACES",
      "In person" => "IN_PERSON"
    }.freeze

    DEPARTMENTS = ["Sales", "Procurement", "Finance", "Operations", "Warehouse & logistics", "Customer service",
                   "HR", "IT", "Marketing", "Administration", "Management"].freeze

    # O8 is a seed for the technology landscape: kinds of system, plus the names
    # the client types under Other.
    SYSTEMS = ["ERP", "CRM", "Accounting software", "HR or payroll system", "E-commerce platform",
               "Document storage", "Microsoft 365", "Google Workspace", "Spreadsheets", "Custom-built system"].freeze

    DATA_STORAGE = ["Cloud suite (Microsoft 365, Google Workspace)", "Shared network drives", "Local servers",
                    "Inside the ERP or CRM", "Spreadsheets", "A mix of these"].freeze

    NO_AI = "None"
    AI_TOOLS = [NO_AI, "ChatGPT", "Microsoft Copilot", "Google Gemini", "Claude", "AI built into our existing software",
                "A chatbot on our website"].freeze

    CONSTRAINTS = ["Data must stay in the country", "Industry regulation", "Security certification (e.g. ISO 27001)",
                   "Client confidentiality obligations", "Internal rules on cloud systems",
                   "Internal rules on AI tools"].freeze

    LANGUAGES = { "English" => "en", "Arabic" => "ar" }.freeze

    FIELDS = [
      { key: "o01_industry", type: :single, options: INDUSTRIES.keys, with_other: true },
      { key: "o01_industry_detail", type: :text, max: 120 },
      { key: "o02_headcount", type: :single, options: HEADCOUNTS.keys },
      { key: "o03_hq_country", type: :text, max: 80 },
      { key: "o03_locations", type: :text, max: 300 },
      { key: "o04_business_model", type: :multi, options: BUSINESS_MODELS.keys, with_other: true },
      { key: "o05_products_services", type: :textarea, max: 400 },
      { key: "o06_departments", type: :multi, options: DEPARTMENTS, with_other: true },
      { key: "o07_channels", type: :multi, options: CHANNELS.keys, with_other: true },
      { key: "o08_systems", type: :multi, options: SYSTEMS, with_other: true },
      { key: "o09_data_storage", type: :multi, options: DATA_STORAGE, with_other: true },
      { key: "o10_ai_tools", type: :multi, options: AI_TOOLS, with_other: true },
      { key: "o11_constraints", type: :multi, options: CONSTRAINTS, with_other: true },
      # P1's options are the client's own departments (O6 and the engagement's
      # scope), so any short name is allowed; scope is checked on submit.
      { key: "p1_departments", type: :list, max: 60 },
      { key: "p2_department_counts", type: :per_item_numeric, source: "p1_departments" },
      { key: "a4_language", type: :single, options: LANGUAGES.keys, no_unknown: true }
    ].freeze

    FIELD_IDS = FIELDS.map { |f| f[:key] }.freeze
    BY_KEY = FIELDS.to_h { |f| [f[:key], f] }.freeze
    OTHER_KEYS = FIELDS.filter_map { |f| "#{f[:key]}_other" if f[:with_other] }.freeze
    WHITELIST = (FIELD_IDS + OTHER_KEYS).freeze
    OTHER_TEXT_MAX_LENGTH = 200
    MAX_COUNT = 9_999

    # The acknowledgement the key user ticks (A5). Versioned so we always know
    # which wording someone agreed to; change the text, change the version.
    CONFIDENTIALITY_VERSION = "2026-11-03"
    CONFIDENTIALITY_TEXT = <<~TEXT.squish
      I confirm I'm authorised to share information about %<company>s with Mjadi. I understand that Mjadi will use
      what we provide — this form, our conversations, uploaded documents and any recordings — only to understand how
      our work is done and to prepare our reports. What individual staff say is not shown to me or other colleagues;
      reports describe work, not people. Recordings are transcribed and kept only as long as our engagement terms
      allow; documents are handled according to our engagement terms.
    TEXT

    # Keeps what may be stored and drops the rest; returns [clean, errors].
    def self.sanitize(raw)
      errors = []
      clean = raw.to_h.stringify_keys.slice(*WHITELIST).each_with_object({}) do |(key, value), out|
        result = OTHER_KEYS.include?(key) ? clean_text(value, OTHER_TEXT_MAX_LENGTH) : clean_value(BY_KEY[key], value)
        if result == :invalid
          errors << "#{key} has a value that isn't one of its options"
        elsif result == :too_long
          errors << "#{key} is too long"
        else
          out[key] = result
        end
      end
      [clean, errors]
    end

    def self.not_sure?(value)
      value == NOT_SURE || (value.is_a?(Array) && value == [NOT_SURE])
    end

    def self.clean_value(field, value)
      return nil if value.nil?
      # Kept in the shape it came in — ["Not sure"] for a multi-select — so the
      # form shows the choice the key user made.
      return value.is_a?(Array) ? [NOT_SURE] : NOT_SURE if not_sure?(value) && !field[:no_unknown]

      case field[:type]
      when :single
        text = value.to_s.strip
        return nil if text.empty?

        field[:options].include?(text) || (field[:with_other] && text == OTHER) ? text : :invalid
      when :multi
        list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?).uniq
        allowed = field[:options] + (field[:with_other] ? [OTHER] : [])
        (list - allowed).empty? ? list : :invalid
      when :list
        list = Array(value).map { |v| v.to_s.gsub(/[[:cntrl:]]/, "").strip }.reject(&:empty?).uniq.first(30)
        list.any? { |v| v.length > field[:max] } ? :too_long : list
      when :per_item_numeric
        return :invalid unless value.is_a?(Hash) || value.respond_to?(:to_unsafe_h)

        hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
        hash.each_with_object({}) do |(item, count), out|
          count = count.to_s.strip
          next if count.empty?
          return :invalid unless count == NOT_SURE || (count.match?(/\A\d+\z/) && count.to_i <= MAX_COUNT)

          out[item.to_s.strip.first(60)] = count
        end
      else
        clean_text(value, field[:max])
      end
    end

    def self.clean_text(value, max)
      text = value.to_s.gsub(/[[:cntrl:]&&[^\n]]/, "").strip
      text.length > max ? :too_long : text
    end
  end
end
