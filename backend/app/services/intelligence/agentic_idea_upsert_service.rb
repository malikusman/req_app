# frozen_string_literal: true

module Intelligence
  class AgenticIdeaUpsertService
    def self.call(company:, ideas:, actor: nil)
      new(company: company, ideas: ideas, actor: actor).call
    end

    def initialize(company:, ideas:, actor: nil)
      @company = company
      @ideas = ideas
      @actor = actor
    end

    def call
      Array(@ideas).filter_map do |attrs|
        title = attrs[:title].presence || attrs["title"].presence
        next if title.blank?

        # Only auto-upsert generated drafts; never clobber human-edited rows.
        record = @company.agentic_ideas.find_or_initialize_by(title: title, source: "generated")
        next record if record.persisted? && record.status != "draft"

        record.assign_attributes(
          summary: attrs[:summary] || attrs["summary"],
          system_fit: attrs[:system_fit] || attrs["system_fit"],
          value_time: attrs[:value_time] || attrs["value_time"],
          value_efficiency: attrs[:value_efficiency] || attrs["value_efficiency"],
          value_cost: attrs[:value_cost] || attrs["value_cost"],
          approx_timeline: attrs[:approx_timeline] || attrs["approx_timeline"],
          estimated_cost: attrs[:estimated_cost] || attrs["estimated_cost"],
          confidence: attrs[:confidence] || attrs["confidence"] || 0.5,
          status: "draft",
          source: "generated",
          related_signal_ids: Array(attrs[:related_signal_ids] || attrs["related_signal_ids"]),
          related_pattern_ids: Array(attrs[:related_pattern_ids] || attrs["related_pattern_ids"]),
          related_stack_ids: Array(attrs[:related_stack_ids] || attrs["related_stack_ids"]),
          solution_catalog_entry_id: attrs[:solution_catalog_entry_id] || attrs["solution_catalog_entry_id"]
        )
        if @actor && record.new_record?
          record.created_by_type = @actor.class.name
          record.created_by_id = @actor.id
        end
        record.save!
        record
      end
    end
  end
end
