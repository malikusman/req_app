# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health check", type: :request do
  describe "GET /up" do
    it "returns success" do
      get "/up"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /health/ready" do
    it "returns ok when database, redis, and sidekiq are reachable" do
      get "/health/ready"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["checks"]).to eq(
        "database" => true,
        "redis" => true,
        "sidekiq" => true
      )
    end

    it "returns 503 when redis is down" do
      allow(REDIS).to receive(:ping).and_raise(Redis::CannotConnectError)
      get "/health/ready"
      expect(response).to have_http_status(:service_unavailable)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("unavailable")
      expect(body["checks"]["redis"]).to eq(false)
    end

    it "returns 503 when the database is down" do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(false)
      get "/health/ready"
      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["checks"]["database"]).to eq(false)
    end
  end
end
