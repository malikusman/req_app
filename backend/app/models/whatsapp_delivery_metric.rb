# frozen_string_literal: true

class WhatsappDeliveryMetric < ApplicationRecord
  METRIC_TYPES = %w[template_sent template_failed api_error webhook_lag_ms].freeze

  def self.record!(metric_type, count: 1, metadata: {})
    bucket = Time.current.beginning_of_hour
    row = find_or_initialize_by(hour_bucket: bucket, metric_type: metric_type)
    row.count = row.count.to_i + count
    row.metadata = row.metadata.merge(metadata.stringify_keys)
    row.save!
  end
end
