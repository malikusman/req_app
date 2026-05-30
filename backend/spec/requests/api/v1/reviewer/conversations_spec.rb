# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Reviewer::Conversations", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:reviewer) { create(:reviewer_user, email: "reviewer-conv-#{SecureRandom.hex(4)}@example.com") }
  let!(:assignment) { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }
  let!(:employee) { company.employees.create!(phone_e164: "+14155559999", display_name: "Sam", participation_status: "started", onboarding_step: "verified", invited_at: Time.current) }
  let!(:conversation) { Conversation.create!(company: company, employee: employee, status: "discovery") }
  let!(:message) { Message.create!(conversation: conversation, direction: "inbound", message_type: "audio", processing_status: "failed", body: nil) }
  let!(:attachment) do
    MediaAttachment.create!(
      message: message,
      company: company,
      employee: employee,
      conversation: conversation,
      attachment_type: "audio",
      status: "failed",
      processing_error: "transcription failed"
    )
  end

  describe "POST /api/v1/reviewer/companies/:company_id/conversations/:id/messages/:message_id/reprocess" do
    it "queues media reprocessing for failed attachment" do
      post "/api/v1/reviewer/companies/#{company.id}/conversations/#{conversation.id}/messages/#{message.id}/reprocess",
           headers: auth_headers_for(reviewer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to eq(true)
      expect(attachment.reload.status).to eq("pending")
      expect(message.reload.processing_status).to eq("pending")
    end
  end
end
