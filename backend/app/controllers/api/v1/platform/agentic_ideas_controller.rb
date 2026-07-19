# frozen_string_literal: true

module Api
  module V1
    module Platform
      class AgenticIdeasController < BaseController
        include AgenticIdeasRendering

        before_action :set_company

        def index
          ideas = @company.agentic_ideas.active_backlog.order(updated_at: :desc)
          render json: { agentic_ideas: ideas.map { |i| idea_json(i) } }
        end

        def create
          idea = @company.agentic_ideas.new(idea_write_params)
          idea.source = "platform"
          idea.status = idea.status.presence || "draft"
          idea.created_by_type = current_platform_user.class.name
          idea.created_by_id = current_platform_user.id
          idea.save!
          render json: { agentic_idea: idea_json(idea) }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end

        def update
          idea = @company.agentic_ideas.find(params[:id])
          idea.assign_attributes(idea_write_params)
          idea.updated_by_type = current_platform_user.class.name
          idea.updated_by_id = current_platform_user.id
          idea.published_at = Time.current if idea.status_changed? && idea.status == "published" && idea.published_at.blank?
          idea.save!
          render json: { agentic_idea: idea_json(idea) }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end

        def publish
          idea = @company.agentic_ideas.find(params[:id])
          idea.publish!(actor: current_platform_user)
          render json: { agentic_idea: idea_json(idea) }
        end

        def archive
          idea = @company.agentic_ideas.find(params[:id])
          idea.archive!(actor: current_platform_user)
          render json: { agentic_idea: idea_json(idea) }
        end

        def synthesize
          ideas = Intelligence::AgenticIdeaSynthesizer.call(company: @company)
          saved = Intelligence::AgenticIdeaUpsertService.call(
            company: @company,
            ideas: ideas,
            actor: current_platform_user
          )
          render json: { agentic_ideas: @company.agentic_ideas.active_backlog.order(updated_at: :desc).map { |i| idea_json(i) }, synthesized: saved.size }
        end

        private

        def set_company
          @company = ::Company.find(params[:company_id])
        end
      end
    end
  end
end
