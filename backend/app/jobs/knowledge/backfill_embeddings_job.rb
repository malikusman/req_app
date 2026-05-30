# frozen_string_literal: true

module Knowledge
  class BackfillEmbeddingsJob < ApplicationJob
    queue_as :low

    def perform(company_id = nil)
      scope = company_id ? Company.where(id: company_id) : Company.all
      scope.find_each do |company|
        Knowledge::IndexProfileService.call(company: company)
        company.conversation_insights.find_each do |insight|
          Knowledge::IndexInsightService.call(insight: insight)
        end
      end
    end
  end
end
