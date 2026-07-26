# frozen_string_literal: true

module Companies
  # Persists firmographic company_profile JSON and seeds CompanySystem rows for known tools.
  class ProfileUpdater
    PROFILE_KEYS = %w[
      industry sub_industry size_band region country annual_revenue_band
      business_goals org_departments
    ].freeze

    CATEGORY_HINTS = {
      "erp" => /\b(sap|oracle|netsuite|dynamics|erp)\b/i,
      "spreadsheet" => /\b(excel|sheets|spreadsheet)\b/i,
      "tms" => /\b(tms|freight|logistics)\b/i,
      "messaging" => /\b(slack|teams|whatsapp|email)\b/i,
      "crm" => /\b(salesforce|hubspot|crm)\b/i,
      "finance" => /\b(quickbooks|xero|workday|finance)\b/i,
      "warehouse" => /\b(wms|warehouse)\b/i
    }.freeze

    def self.call(company:, profile_params: {}, known_systems: nil, website_url: :omit)
      new(
        company: company,
        profile_params: profile_params,
        known_systems: known_systems,
        website_url: website_url
      ).call
    end

    def initialize(company:, profile_params: {}, known_systems: nil, website_url: :omit)
      @company = company
      @profile_params = profile_params
      @known_systems = known_systems
      @website_url = website_url
    end

    def call
      profile = (@company[:company_profile] || {}).to_h.stringify_keys
      PROFILE_KEYS.each do |key|
        next unless @profile_params.key?(key) || @profile_params.key?(key.to_sym)

        value = @profile_params[key] || @profile_params[key.to_sym]
        profile[key] = normalize_value(key, value)
      end

      attrs = { company_profile: profile }
      previous_website = @company.website_url
      if @website_url != :omit
        attrs[:website_url] = normalize_website(@website_url)
      end

      @company.update!(attrs)
      sync_known_systems! if !@known_systems.nil?

      if @website_url != :omit && @company.website_url.present? && @company.website_url != previous_website
        CompanyWebResearchJob.perform_later(@company.id)
      end

      @company
    end

    private

    def normalize_website(value)
      url = value.to_s.strip.presence
      return nil if url.blank?

      url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
      url
    end

    def normalize_value(key, value)
      case key
      when "business_goals"
        if value.is_a?(Array)
          value.map { |v| v.to_s.strip }.reject(&:blank?).first(12)
        else
          value.to_s.strip
        end
      when "org_departments"
        Array(value).map { |v| v.to_s.strip }.reject(&:blank?).uniq.first(30)
      else
        value.to_s.strip.presence
      end
    end

    def sync_known_systems!
      names = Array(@known_systems).map { |n| n.to_s.strip }.reject(&:blank?).uniq.first(20)
      return if names.empty?

      names.each do |name|
        normalized = CompanySystem.normalize(name)
        next if normalized.blank?

        system = @company.company_systems.find_or_initialize_by(normalized_name: normalized)
        system.assign_attributes(
          name: name,
          category: infer_category(name),
          source: "manual",
          confidence: 1.0,
          active: true
        )
        system.save!
      end
    end

    def infer_category(name)
      CATEGORY_HINTS.each do |category, pattern|
        return category if name.match?(pattern)
      end
      "other"
    end
  end
end
