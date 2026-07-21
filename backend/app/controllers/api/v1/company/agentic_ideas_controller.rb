# frozen_string_literal: true

module Api
  module V1
    module Company
      class AgenticIdeasController < BaseController
        include AgenticIdeasRendering

        def index
          ideas = current_company.agentic_ideas.published.order(confidence: :desc)
          render json: { agentic_ideas: ideas.map { |i| idea_json(i) } }
        end
      end
    end
  end
end
