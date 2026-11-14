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

    # Each run regenerates the company's ideas from its current evidence. An idea
    # that matches one already held (Intelligence::IdeaMatching) is that idea:
    # an unreviewed generated draft is refreshed in place, and anything a person
    # has published or written stands untouched. Generated drafts this run did not
    # produce again are archived — the evidence moved on — never deleted.
    def call
      existing = @company.agentic_ideas.active_backlog.to_a
      touched = []
      saved = Array(@ideas).filter_map do |attrs|
        title = attrs[:title].presence || attrs["title"].presence
        next if title.blank?
        next if touched.any? { |t| IdeaMatching.same?(t.title, title) } # a repeat within this run

        record = existing.find { |i| i.title == title } || existing.find { |i| IdeaMatching.same?(i.title, title) }
        record ||= @company.agentic_ideas.new(title: title, source: "generated")
        touched << record
        # Only auto-upsert generated drafts; never clobber human-edited rows.
        next record if record.persisted? && (record.status != "draft" || record.source != "generated")

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
      archive_superseded!(touched)
      saved
    end

    private

    def archive_superseded!(touched)
      return if touched.empty?

      @company.agentic_ideas.where(status: "draft", source: "generated")
              .where.not(id: touched.map(&:id).compact)
              .update_all(status: "archived", updated_at: Time.current)
    end
  end
end
