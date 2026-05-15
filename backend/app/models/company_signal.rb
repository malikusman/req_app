# frozen_string_literal: true

class CompanySignal < ApplicationRecord
  belongs_to :company

  STATUSES = %w[emerging confirmed].freeze
  TYPES = %w[manual_process tool_dependency approval_bottleneck data_silo time_sink communication].freeze

  validates :label, :signal_type, :first_seen_at, :last_updated_at, presence: true
  validates :signal_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }

  def record_strength!(new_strength)
    history = strength_history + [{ "strength" => strength, "at" => Time.current.iso8601 }]
    update!(
      strength: new_strength,
      strength_history: history,
      last_updated_at: Time.current,
      status: new_strength >= 0.7 ? "confirmed" : status
    )
  end
end
