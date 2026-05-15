# frozen_string_literal: true

module Api
  module V1
    module Platform
      class SystemController < BaseController
        def show
          render json: {
            services: {
              langgraph: check_langgraph,
              gotenberg: check_gotenberg,
              redis: check_redis
            },
            whatsapp_delivery: whatsapp_health
          }
        end

        private

        def check_langgraph
          uri = URI("#{ENV.fetch('LANGGRAPH_URL', 'http://langgraph:8000')}/health")
          response = Net::HTTP.get_response(uri)
          { status: response.is_a?(Net::HTTPSuccess) ? "ok" : "error", detail: JSON.parse(response.body) }
        rescue StandardError => e
          { status: "error", detail: e.message }
        end

        def check_gotenberg
          uri = URI("#{ENV.fetch('GOTENBERG_URL', 'http://gotenberg:3000')}/health")
          response = Net::HTTP.get_response(uri)
          { status: response.is_a?(Net::HTTPSuccess) ? "ok" : "error" }
        rescue StandardError => e
          { status: "unavailable", detail: e.message }
        end

        def check_redis
          REDIS.ping
          { status: "ok" }
        rescue StandardError => e
          { status: "error", detail: e.message }
        end

        def whatsapp_health
          since = 24.hours.ago
          metrics = WhatsappDeliveryMetric.where("hour_bucket >= ?", since).group(:metric_type).sum(:count)

          {
            last_24h: metrics,
            template_sent: metrics["template_sent"].to_i,
            template_failed: metrics["template_failed"].to_i,
            api_errors: metrics["api_error"].to_i,
            failure_rate: failure_rate(metrics)
          }
        end

        def failure_rate(metrics)
          sent = metrics["template_sent"].to_i
          failed = metrics["template_failed"].to_i + metrics["api_error"].to_i
          return 0.0 if sent.zero?

          (failed.to_f / (sent + failed) * 100).round(1)
        end
      end
    end
  end
end
