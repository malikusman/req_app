# frozen_string_literal: true

class HealthController < ApplicationController
  def ready
    checks = {
      database: database_ok?,
      redis: redis_ok?,
      sidekiq: sidekiq_ok?
    }

    if checks.values.all?
      render json: { status: "ok", checks: checks }, status: :ok
    else
      render json: { status: "unavailable", checks: checks }, status: :service_unavailable
    end
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.active?
  rescue StandardError
    false
  end

  def redis_ok?
    REDIS.ping == "PONG"
  rescue StandardError
    false
  end

  def sidekiq_ok?
    Sidekiq.redis { |conn| conn.ping == "PONG" }
  rescue StandardError
    false
  end
end
