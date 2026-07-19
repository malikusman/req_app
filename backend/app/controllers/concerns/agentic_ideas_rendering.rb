# frozen_string_literal: true

module AgenticIdeasRendering
  extend ActiveSupport::Concern

  private

  def idea_json(idea)
    {
      id: idea.id,
      company_id: idea.company_id,
      title: idea.title,
      summary: idea.summary,
      system_fit: idea.system_fit,
      value_time: idea.value_time,
      value_efficiency: idea.value_efficiency,
      value_cost: idea.value_cost,
      approx_timeline: idea.approx_timeline,
      estimated_cost: idea.estimated_cost,
      confidence: idea.confidence,
      status: idea.status,
      source: idea.source,
      related_signal_ids: idea.related_signal_ids,
      related_pattern_ids: idea.related_pattern_ids,
      related_stack_ids: idea.related_stack_ids,
      solution_catalog_entry_id: idea.solution_catalog_entry_id,
      catalog_name: idea.solution_catalog_entry&.name,
      published_at: idea.published_at,
      created_at: idea.created_at,
      updated_at: idea.updated_at
    }
  end

  def idea_write_params
    params.require(:agentic_idea).permit(
      :title, :summary, :system_fit, :value_time, :value_efficiency, :value_cost,
      :approx_timeline, :estimated_cost, :confidence, :status, :solution_catalog_entry_id,
      related_signal_ids: [], related_pattern_ids: [], related_stack_ids: []
    )
  end
end
