# frozen_string_literal: true

module Knowledge
  class IndexInsightJob < ApplicationJob
    queue_as :default

    def perform(insight_id)
      insight = ConversationInsight.find_by(id: insight_id)
      return unless insight

      Knowledge::IndexInsightService.call(insight: insight)
    end
  end
end
