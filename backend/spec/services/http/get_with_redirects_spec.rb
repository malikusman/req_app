# frozen_string_literal: true

require "rails_helper"

RSpec.describe Http::GetWithRedirects do
  it "follows relative redirects and returns the final body" do
    stub_request(:get, "https://example.com/old")
      .to_return(status: 301, headers: { "Location" => "/new" })
    stub_request(:get, "https://example.com/new")
      .to_return(status: 200, body: "ok")

    result = described_class.call("https://example.com/old")

    expect(result).to be_success
    expect(result.body).to eq("ok")
    expect(result.final_url).to eq("https://example.com/new")
  end

  it "rejects hops that fail validation" do
    stub_request(:get, "https://example.com/start")
      .to_return(status: 302, headers: { "Location" => "https://evil.example/secret" })

    result = described_class.call(
      "https://example.com/start",
      validate: ->(url) { !url.include?("evil.example") }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("unsafe_url")
  end

  it "returns http status errors without following further" do
    stub_request(:get, "https://example.com/blocked").to_return(status: 403, body: "no")

    result = described_class.call("https://example.com/blocked")

    expect(result).not_to be_success
    expect(result.error).to eq("http_403")
    expect(result.status_code).to eq(403)
  end
end
