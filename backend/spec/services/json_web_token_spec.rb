# frozen_string_literal: true

require "rails_helper"

RSpec.describe JsonWebToken do
  describe ".encode and .decode" do
    it "round-trips a payload" do
      payload = { sub: "company_user:1", aud: "company", company_id: 42, jti: "abc" }
      token = described_class.encode(payload, expires_at: 1.hour.from_now)
      decoded = described_class.decode(token)

      expect(decoded[:sub]).to eq("company_user:1")
      expect(decoded[:aud]).to eq("company")
      expect(decoded[:company_id]).to eq(42)
      expect(decoded[:jti]).to eq("abc")
      expect(decoded[:exp]).to be_present
    end

    it "returns nil for invalid tokens" do
      expect(described_class.decode("not-a-jwt")).to be_nil
    end
  end
end
