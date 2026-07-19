# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public demo requests", type: :request do
  let(:valid_params) do
    { name: "Jordan Lee", email: "jordan@example.com", company_name: "Acme Corp", role: "Operations", notes: "Docs-first pilot" }
  end

  it "creates a demo request and enqueues the sales notification" do
    expect {
      post "/api/v1/public/demo_requests", params: valid_params
    }.to change(DemoRequest, :count).by(1)
      .and have_enqueued_mail(DemoRequestMailer, :notify)

    expect(response).to have_http_status(:created)
    request_record = DemoRequest.last
    expect(request_record.email).to eq("jordan@example.com")
    expect(request_record.status).to eq("new")
  end

  it "rejects invalid submissions" do
    post "/api/v1/public/demo_requests", params: valid_params.merge(email: "not-an-email")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"]).to be_present
  end

  it "silently drops honeypot submissions" do
    expect {
      post "/api/v1/public/demo_requests", params: valid_params.merge(website: "http://spam.example")
    }.not_to change(DemoRequest, :count)

    expect(response).to have_http_status(:created)
  end
end
