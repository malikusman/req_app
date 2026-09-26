# frozen_string_literal: true

require "rails_helper"

# Every employee accepts consent text that says "only summarized insights are
# shared with authorized leads — not raw chat logs or original files". These
# examples hold the client portal to that: it may see who has taken part, never
# what anyone said or sent.
RSpec.describe "Client access to employee interviews", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:company_user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(company_user) }
  let(:employee) do
    create(:employee, company: company, participation_status: "completed",
                      metadata: { "profile" => { "responsibilities" => "I re-key supplier prices every morning" } })
  end
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }
  let!(:message) do
    create(:message, conversation: conversation, direction: "inbound", body: "Honestly the ERP export is useless")
  end

  it "has no transcript list or transcript endpoint" do
    get "/api/v1/company/conversations", headers: headers
    expect(response).to have_http_status(:not_found)

    get "/api/v1/company/conversations/#{conversation.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "has no way to list or download what an employee sent" do
    attachment = create(:media_attachment, message: message, status: "ready")

    get "/api/v1/company/media_attachments", headers: headers
    expect(response).to have_http_status(:not_found)

    get "/api/v1/company/media_attachments/#{attachment.id}/download", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "does not show the questions the interviewer asked, which paraphrase the answers" do
    get "/api/v1/company/discovery_questions", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "shows participation status for each employee, without their own words" do
    employee

    get "/api/v1/company/employees", headers: headers

    expect(response).to have_http_status(:ok)
    row = JSON.parse(response.body)["employees"].find { |e| e["id"] == employee.id }
    expect(row["participation_status"]).to eq("completed")
    expect(row).not_to have_key("profile")
    expect(response.body).not_to include("re-key supplier prices")
  end

  it "keeps text read from employee media out of the signal feed" do
    create(:company_signal, company: company, metadata: {
      "multimodal_evidence" => [{ "excerpt" => "screenshot of my SAP screen", "conversation_id" => conversation.id }]
    })

    get "/api/v1/company/intelligence/signals", headers: headers

    expect(response).to have_http_status(:ok)
    signal = JSON.parse(response.body)["signals"].first
    expect(signal).not_to have_key("multimodal_evidence")
    expect(response.body).not_to include("SAP screen")
  end

  it "reports that a digest exists without handing over what it says" do
    EmployeeValueDigest.create!(
      employee: employee, company: company, period_key: "2026-09",
      content: { "headline" => "Your personal workflow insights",
                 "insights" => [{ "summary" => "Employee said: the ERP export is useless" }],
                 "tips" => ["Try a saved export view"] }
    )

    get "/api/v1/company/employees/#{employee.id}/value_preference", headers: headers

    expect(response).to have_http_status(:ok)
    digest = JSON.parse(response.body)["latest_digest"]
    expect(digest["headline"]).to eq("Your personal workflow insights")
    expect(digest["tip_count"]).to eq(1)
    expect(digest).not_to have_key("content")
    expect(response.body).not_to include("ERP export is useless")
  end
end
