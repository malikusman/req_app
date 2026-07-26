# frozen_string_literal: true

module Companies
  # Shared firmographic + stack pack for agents, reports, and reviewer APIs.
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

    def self.docs_profile_snapshot(company)
      {
        "name" => company.name,
        "display_name" => company.display_name,
        "website_url" => company.try(:website_url).presence,
        "company_profile" => profile_slice(company),
        "questionnaire_answers" => company.questionnaire_answers || {},
        "known_systems" => known_systems(company),
        "locale" => company.locale
      }.compact
    end

    def self.reviewer_profile_json(company)
      {
        "company_profile" => profile_slice(company),
        "website_url" => company.try(:website_url),
        "company_systems" => known_systems(company),
        "web_research" => web_research_entries(company),
        "questionnaire_summary" => {
          "industry" => company.profile_value("industry"),
          "size_band" => company.profile_value("size_band"),
          "business_goals" => company.profile_value("business_goals"),
          "org_departments" => company.profile_value("org_departments"),
          "systems" => known_systems(company).map { |s| s["name"] }
        }.compact
      }
    end
  end
end
