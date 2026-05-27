# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::SignatureVerifier do
  describe ".valid?" do
    around do |example|
      previous = ENV["META_APP_SECRET"]
      ENV["META_APP_SECRET"] = "test-secret"
      example.run
    ensure
      ENV["META_APP_SECRET"] = previous
    end

    it "returns true when signature matches payload" do
      payload = '{"entry":[]}'
      signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "test-secret", payload)

      expect(described_class.valid?(payload, signature)).to be true
    end

    it "returns false when signature is wrong" do
      expect(described_class.valid?('{"entry":[]}', "sha256=deadbeef")).to be false
    end

    it "returns false when signature header is blank" do
      expect(described_class.valid?("{}", nil)).to be false
    end
  end
end
