# frozen_string_literal: true

class ProcessWhatsappWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Whatsapp::InboundProcessor.new(payload).process
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    WhatsappDeliveryMetric.record!("webhook_lag_ms", metadata: { elapsed_ms: elapsed_ms })
  end
end
