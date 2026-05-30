# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::ReviewerChat", type: :request do
  let!(:platform_user) { create(:platform_user) }
  let!(:company) { create(:company, :onboarded) }
  let!(:reviewer_one) { create(:reviewer_user, email: "chat-r1-#{SecureRandom.hex(4)}@example.com") }
  let!(:reviewer_two) { create(:reviewer_user, email: "chat-r2-#{SecureRandom.hex(4)}@example.com") }
  let!(:assignment_one) { create(:reviewer_assignment, company: company, reviewer_user: reviewer_one) }
  let!(:assignment_two) { create(:reviewer_assignment, company: company, reviewer_user: reviewer_two) }

  it "allows platform to post in reviewer collaboration chat" do
    post "/api/v1/platform/companies/#{company.id}/reviewer_chat",
         params: { body: "Please align on recommendation ownership." },
         headers: auth_headers_for(platform_user),
         as: :json

    expect(response).to have_http_status(:created)
    message = ReviewerChatMessage.order(:created_at).last
    expect(message.sender_role).to eq("platform")
    expect(message.sender_platform_user_id).to eq(platform_user.id)
  end
end
