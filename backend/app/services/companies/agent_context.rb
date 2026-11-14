# frozen_string_literal: true

module Companies
  # Shared firmographic + stack pack for agents, reports, and consultant APIs.
  class AgentContext
    PROFILE_KEYS = ProfileUpdater::PROFILE_KEYS

    def self.profile_slice(company)
      (company.company_profile || {}).slice(*PROFILE_KEYS)
    end

    def self.known_systems(company)
      return [] unless defined?(CompanySystem) && CompanySystem.table_exists?

      company.company_systems.active.order(:name).limit(30).map do |sys|
        {
          "name" => sys.name,
          "category" => sys.category,
          "source" => sys.source,
          "confidence" => sys.confidence
        }
      end
    end

    def self.web_research_entries(company, limit: 5)
      return [] unless company.respond_to?(:company_knowledge_entries)

      company.company_knowledge_entries
        .active
        .where("metadata->>'source' = ?", "web_research")
        .order(updated_at: :desc)
        .limit(limit)
        .map do |e|
          {
            "id" => e.id,
            "title" => e.title,
            "content" => e.content.to_s.truncate(800),
            "url" => e.metadata["url"],
            "fetched_at" => e.metadata["fetched_at"] || e.updated_at&.iso8601,
            "confidence" => e.confidence
          }
        end
    end

    # Payload nested under company_profile for LangGraph / discovery.
    def self.for_agents(company)
      slice = profile_slice(company)
      systems = known_systems(company)
      {
        **slice,
        "website_url" => company.try(:website_url).presence,
        "known_systems" => systems.map { |s| s["name"] },
        "client_stack" => systems
      }.compact
    end

    # What document analysis may know about the company: the confirmed profile and
    # its systems. Never the questionnaire answers — those held management's goals
    # and pain points, and analysis output becomes knowledge that employee
    # interviews read.
    def self.docs_profile_snapshot(company)
      {
        "name" => company.name,
        "display_name" => company.display_name,
        "website_url" => company.try(:website_url).presence,
        "company_profile" => profile_slice(company),
        "known_systems" => known_systems(company),
        "locale" => company.locale
      }.compact
    end

    # The only part of the conversations with leadership that may reach an
    # employee interview (Doc 08 §18.1): short neutral lines for a department —
    # "The company wants to respond to customer enquiries faster" — already
    # checked for attribution, names, solutions and figures when they were
    # written (KeyPerson::ContextValidator). Lines for the whole company apply to
    # every department. Not added to for_agents: the employee interview opts in.
    COMPANY_WIDE = %w[company all company-wide everyone].freeze

    def self.neutral_management_context(company, department:)
      engagement = company.current_engagement
      return [] unless engagement

      wanted = department.to_s.strip.downcase
      ManagementDiscoveryContext.where(engagement: engagement).latest_per_participant.flat_map do |context|
        Array(context.neutral_employee_context).filter_map do |line|
          dept = line["department"].to_s.strip.downcase
          line["context"] if dept == wanted || COMPANY_WIDE.include?(dept)
        end
      end.uniq
    end

    def self.consultant_profile_json(company)
      {
        "company_profile" => profile_slice(company),
        "website_url" => company.try(:website_url),
        "company_systems" => known_systems(company),
        "web_research" => web_research_entries(company),
        "questionnaire_summary" => {
          "industry" => company.profile_value("industry"),
          "size_band" => company.profile_value("size_band"),
          "org_departments" => company.profile_value("org_departments"),
          "systems" => known_systems(company).map { |s| s["name"] }
        }.compact,
        # The old questionnaire's goals and revenue band, kept for consultants only.
        # Nothing the AI reads draws on this.
        "legacy_profile" => legacy_for_consultant(company)
      }.compact
    end

    def self.legacy_for_consultant(company)
      legacy = (company.try(:legacy_profile) || {}).slice("business_goals", "annual_revenue_band")
      legacy.presence
    end
  end
end
