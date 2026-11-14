# frozen_string_literal: true

namespace :intelligence do
  desc "Archive near-duplicate generated idea drafts (published and human ideas are never touched). SLUG=… for one company"
  task dedupe_ideas: :environment do
    companies = ENV["SLUG"].present? ? Company.where(slug: ENV["SLUG"]) : Company.all
    companies.find_each do |company|
      # Published first, then human-written, then newest: the first of each group
      # of same ideas is the one kept.
      ideas = company.agentic_ideas.active_backlog.to_a.sort_by do |i|
        [i.status == "published" ? 0 : 1, i.source == "generated" ? 1 : 0, -i.updated_at.to_i]
      end
      kept = []
      archived = 0
      ideas.each do |idea|
        if kept.any? { |k| Intelligence::IdeaMatching.same?(k.title, idea.title) } &&
           idea.status == "draft" && idea.source == "generated"
          idea.update_columns(status: "archived", updated_at: Time.current)
          archived += 1
        else
          kept << idea
        end
      end
      puts "#{company.slug}: #{ideas.size} active ideas, archived #{archived} repeats, #{kept.size} kept" if ideas.any?
    end
  end
end
