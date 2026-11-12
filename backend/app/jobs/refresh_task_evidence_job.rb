# frozen_string_literal: true

# Runs beside SynthesisRunJob, which reacts to the same interviews; the two
# become one chain (docs/CONSOLIDATION_ENGINES.md §7).
class RefreshTaskEvidenceJob < ApplicationJob
  queue_as :default

  # One drain across the Sidekiq processes. Use a session lock so individual
  # projections and publications can commit or roll back independently.
  ADVISORY_LOCK_ID = 6_804_729_051

  def perform
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      next unless connection.select_value("SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_ID})")

      begin
        TaskEvidenceRefresh.pending_projection.due.find_each { |request| project(request) }
        TaskEvidenceRefresh.pending_publication.due.joins(:conversation).distinct.pluck("conversations.company_id")
                           .each { |company_id| publish(company_id) }
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{ADVISORY_LOCK_ID})")
      end
    end
  end

  private

  def project(request)
    conversation = request.conversation
    return unless conversation

    conversation.with_lock(requires_new: true) do
      request.reload
      next unless request.projection_pending?

      TaskSources::SyncFromConversation.call(conversation: conversation)
      request.update!(**TaskEvidenceRefresh::CLEAR_FAILURE, projection_pending: false)
    end
  rescue StandardError => error
    report_failure([request], "projection", error)
  end

  def publish(company_id)
    scope = TaskEvidenceRefresh.for_company(company_id)
    requests = scope.pending_publication.order(:id).to_a
    return if requests.empty? || requests.any? { |request| request.retry_at&.future? }

    company = Company.find_by(id: company_id)
    return unless company

    run = company.with_lock(requires_new: true) do
      # Avoid publishing a mixture of old and new observations if a source has
      # yet to be projected, including when that projection is backing off.
      next if scope.pending_projection.exists?

      ProcessClusters::Rebuild.call(company: company)
      target = TaskIntelligenceRun.where(company: company).order(version: :desc).pick(:target_size)
      TaskIntelligence::Generate.call(company: company, target: target || TaskIntelligence::Generate::DEFAULT_TARGET)
    end
    return unless run

    # Acknowledge only generations we saw. A concurrent source sync may have
    # created more work while the company was being rebuilt.
    now = Time.current
    requests.each do |request|
      TaskEvidenceRefresh.where(id: request.id, source_generation: request.source_generation)
                         .update_all(**TaskEvidenceRefresh::CLEAR_FAILURE, published_generation: request.source_generation,
                                     last_published_at: now, updated_at: now)
    end
    Rails.logger.info("[RefreshTaskEvidenceJob] company=#{company_id} run=#{run.id} version=#{run.version}")
  rescue StandardError => error
    report_failure(requests, "publication", error, company_id: company_id)
  end

  def report_failure(requests, stage, error, company_id: nil)
    Array(requests).each { |request| request.record_failure!(stage, error) }
    Rails.logger.error(
      "[RefreshTaskEvidenceJob] stage=#{stage} company=#{company_id} requests=#{Array(requests).map(&:id)} error=#{error.class}"
    )
  end
end
