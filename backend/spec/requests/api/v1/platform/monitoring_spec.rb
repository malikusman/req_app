# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Monitoring", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }

  before do
    company = create(:company, settings: { "discovery_multimodal_enabled" => true, "discovery_media_indexing_enabled" => true })
    employee = create(:employee, company: company)
    conversation = create(:conversation, employee: employee, company: company)
    message = create(:message, conversation: conversation, direction: "inbound", message_type: "image")
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "image",
           status: "ready",
           storage_key: "media/test.jpg")
  end

  it "includes multimodal metrics" do
    get "/api/v1/platform/monitoring", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["multimodal"]["ready_attachments"]).to eq(1)
    expect(body["multimodal"]["companies_with_multimodal_enabled"]).to eq(1)
  end
end
