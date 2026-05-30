# frozen_string_literal: true

module Companies
  module AgentFeatures
    DEFAULTS = {
      "multi_agent_discovery" => false,
      "reviewer_copilot" => false,
      "ai_report_narrative" => false,
      "opportunity_scout" => false
    }.freeze

    def self.enabled?(company, feature)
      merged(company)[feature.to_s] == true
    end

    def self.merged(company)
      DEFAULTS.merge((company.settings || {})["agent_features"] || {})
    end
  end
end
