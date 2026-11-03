# frozen_string_literal: true

module Companies
  # Persists firmographic company_profile JSON and seeds CompanySystem rows for known tools.
  #
  # company_profile holds facts only (Doc 07 §13, Doc 06 §3.2). This is the one
  # list of what it may hold, and every writer goes through it, so a field that is
  # not here cannot reach the agents, the report or the consultant view. Revenue,
  # budget, timeline, readiness, goals and pain points are deliberately absent —
  # they are never onboarding facts, whatever an older schema stored.
  #
  # Each written field also records where it came from in profile_provenance, so
  # a value the key user confirmed can be told apart from one they typed, one
  # found later in conversation, or one carried over from the old questionnaire.
  class ProfileUpdater
    PROFILE_KEYS = %w[
      industry industry_detail sub_industry size_band country region locations
      business_model products_services org_departments customer_channels
      data_storage current_ai_use security_constraints
    ].freeze

    LIST_KEYS = %w[locations business_model org_departments customer_channels data_storage current_ai_use].freeze

    PROVENANCE = %w[PREFILL_CONFIRMED USER_ENTERED DISCOVERED_LATER LEGACY_QUESTIONNAIRE].freeze

    # "Not sure" is a real answer (Doc 07 §6): recorded in provenance so the field
    # isn't asked again, but never stored as a value anything could read as fact.
    UNKNOWN = "UNKNOWN"

    CATEGORY_HINTS = {
      "erp" => /\b(sap|oracle|netsuite|dynamics|erp)\b/i,
      "spreadsheet" => /\b(excel|sheets|spreadsheet)\b/i,
      "tms" => /\b(tms|freight|logistics)\b/i,
      "messaging" => /\b(slack|teams|whatsapp|email)\b/i,
      "crm" => /\b(salesforce|hubspot|crm)\b/i,
      "finance" => /\b(quickbooks|xero|workday|finance)\b/i,
      "warehouse" => /\b(wms|warehouse)\b/i
    }.freeze

    # The strong-params filter every controller that edits the profile uses, so the
    # permitted list can't drift between onboarding, settings and registration.
    def self.permit(raw)
      return {} if raw.blank?

      scalars = PROFILE_KEYS - LIST_KEYS
      raw.permit(*scalars, LIST_KEYS.index_with { [] }).to_h
    end

    # only_changed: write a field only when its value differs from what is stored,
    # so saving a whole form again keeps each fact's original provenance.
    def self.call(company:, profile_params: {}, known_systems: nil, website_url: :omit,
                  provenance: "USER_ENTERED", actor: nil, only_changed: false)
      new(
        company: company,
        profile_params: profile_params,
        known_systems: known_systems,
        website_url: website_url,
        provenance: provenance,
        actor: actor,
        only_changed: only_changed
      ).call
    end

    def initialize(company:, profile_params: {}, known_systems: nil, website_url: :omit,
                   provenance: "USER_ENTERED", actor: nil, only_changed: false)
      raise ArgumentError, "unknown provenance #{provenance}" unless PROVENANCE.include?(provenance)

      @company = company
      @profile_params = (profile_params || {}).to_h.stringify_keys
      @known_systems = known_systems
      @website_url = website_url
      @provenance = provenance
      @actor = actor
      @only_changed = only_changed
    end

    def call
      profile = (@company[:company_profile] || {}).to_h.stringify_keys
      provenance = (@company[:profile_provenance] || {}).to_h.stringify_keys
      PROFILE_KEYS.each do |key|
        next unless @profile_params.key?(key)

        value = normalize_value(key, @profile_params[key])
        unknown = unknown?(@profile_params[key])
        next if @only_changed && unchanged?(profile, provenance, key, unknown ? nil : value, unknown)

        if value.nil? || unknown
          profile.delete(key)
        else
          profile[key] = value
        end
        provenance[key] = provenance_entry(unknown: unknown)
      end

      attrs = { company_profile: profile, profile_provenance: provenance }
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

    def unchanged?(profile, provenance, key, value, unknown)
      was_unknown = provenance.dig(key, "unknown") == true
      profile[key] == value && was_unknown == unknown
    end

    def provenance_entry(unknown:)
      entry = { "source" => @provenance, "at" => Time.current.iso8601 }
      entry["unknown"] = true if unknown
      if @actor
        entry["by_type"] = @actor.class.name
        entry["by_id"] = @actor.id
      end
      entry
    end

    def unknown?(value)
      Array(value).map { |v| v.to_s.strip }.include?(UNKNOWN)
    end

    def normalize_website(value)
      url = value.to_s.strip.presence
      return nil if url.blank?

      url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
      url
    end

    def normalize_value(key, value)
      if LIST_KEYS.include?(key)
        list = Array(value).map { |v| v.to_s.strip }.reject(&:blank?).uniq.first(30)
        list.presence
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
        # A system first found in a document or an interview keeps that source:
        # the client naming it too confirms it, it doesn't rewrite its history.
        attrs = { name: name, active: true }
        if system.new_record?
          attrs.merge!(category: infer_category(name), source: "manual", confidence: 1.0)
        else
          attrs[:confidence] = [system.confidence.to_f, 1.0].max
        end
        system.assign_attributes(attrs)
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
