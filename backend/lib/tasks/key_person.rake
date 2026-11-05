# frozen_string_literal: true

require_relative "../key_person_eval"

namespace :key_person do
  desc "Play the key-person benchmark scenarios against the configured model and report critical failures. ONLY=name SCRIPTED=1"
  task eval: :environment do
    KeyPersonEval.call
  end

  # Doc 08 §22, §30: the close reason is the engine's main health measure; a
  # high ceiling rate means the coverage model asks for more than a
  # conversation can give.
  desc "How the conversations with leadership are ending, and how often the model steps fall back. DAYS=30"
  task health: :environment do
    since = Integer(ENV.fetch("DAYS", 30)).days.ago
    sessions = ConversationSession.key_person.where(created_at: since..)
    finished = sessions.where.not(close_reason: nil)
    puts "Conversations since #{since.to_date}: #{sessions.count} (#{finished.count} finished, " \
         "#{sessions.where(state: 'PAUSED').count} paused, #{sessions.where(needs_review: true).count} flagged for review)"
    finished.group(:close_reason).count.sort_by { |_, n| -n }.each do |reason, count|
      puts format("  %-20s %4d  %3d%%", reason, count, (100.0 * count / finished.count).round)
    end
    answers = ConversationTurn.joins(:session).merge(sessions).where(direction: "PARTICIPANT").group(:conversation_session_id).count
    puts "Answers per conversation: average #{answers.values.sum / [answers.size, 1].max}, most #{answers.values.max || 0}"

    runs = AiRun.where(created_at: since..)
    runs.group(:stage).count.sort.each do |stage, total|
      by_status = runs.where(stage: stage).group(:status).count
      fallback = by_status.fetch("FALLBACK", 0) + by_status.fetch("FAILED", 0)
      puts format("  %-4s %5d runs  retried %3d%%  fell back %3d%%  median %s ms", stage, total,
                  (100.0 * by_status.fetch("RETRIED", 0) / total).round, (100.0 * fallback / total).round,
                  runs.where(stage: stage).pick(Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms)"))&.round || "-")
    end
    contexts = ManagementDiscoveryContext.where(created_at: since..)
    puts "Contexts: #{contexts.group(:status).count}"
  end
end
