# frozen_string_literal: true

# Durable work marker. A conversation can have new Discovery evidence to
# project, new TaskSource versions to publish, or both.
class TaskEvidenceRefresh < ApplicationRecord
  belongs_to :conversation

  scope :pending_projection, -> { where(projection_pending: true) }
  scope :pending_publication, -> { where("source_generation > published_generation") }
  scope :due, -> { where("retry_at IS NULL OR retry_at <= ?", Time.current) }
  scope :for_company, ->(company_id) { joins(:conversation).where(conversations: { company_id: company_id }) }

  CLEAR_FAILURE = { attempts: 0, retry_at: nil, failure_stage: nil, last_error_class: nil, last_failure_at: nil }.freeze

  def self.request_projection(conversation_id)
    mark(conversation_id, projection: true, generation: 0)
  end

  def self.record_source_change(conversation_id)
    mark(conversation_id, projection: false, generation: 1)
  end

  def self.mark(conversation_id, projection:, generation:)
    now = Time.current
    upsert({
      conversation_id: conversation_id, projection_pending: projection,
      source_generation: generation, created_at: now, updated_at: now
    }, unique_by: :conversation_id, record_timestamps: false, on_duplicate: Arel.sql(<<~SQL.squish))
      projection_pending = task_evidence_refreshes.projection_pending OR EXCLUDED.projection_pending,
      source_generation = task_evidence_refreshes.source_generation + EXCLUDED.source_generation,
      updated_at = EXCLUDED.updated_at
    SQL
  end
  private_class_method :mark

  def record_failure!(stage, error)
    attempt = attempts + 1
    delay = [2**[attempt - 1, 6].min, 60].min.minutes
    now = Time.current
    self.class.where(id: id).update_all(attempts: attempt, retry_at: now + delay, failure_stage: stage,
                                        last_error_class: error.class.name, last_failure_at: now, updated_at: now)
  end
end
