# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Public::DiscoverSpeech", type: :request do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, onboarding_step: "verified", participation_status: "started") }
  let!(:session) { create(:employee_web_session, employee: employee, company: company, verified_at: Time.current) }
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) { create(:conversation, employee: employee, company: company, status: "discovery") }
  let!(:question) do
    conversation.messages.create!(direction: "outbound", channel: "web", message_type: "text",
                                  body: "What does a normal morning look like?")
  end
  let(:client) { instance_double(Openai::Client, speech_available?: true, speech: "mp3-bytes") }

  before { allow(Openai::Client).to receive(:new).and_return(client) }

  it "speaks the interviewer's question" do
    get "/api/v1/public/discover/messages/#{question.id}/speech", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("audio/mpeg")
    expect(response.body).to eq("mp3-bytes")
    expect(client).to have_received(:speech).with(text: "What does a normal morning look like?")
  end

  it "never reads out the employee's own messages or another conversation's" do
    answer = conversation.messages.create!(direction: "inbound", channel: "web", message_type: "text", body: "Busy.")
    other = create(:conversation, company: company, employee: create(:employee, company: company))
    elsewhere = other.messages.create!(direction: "outbound", channel: "web", message_type: "text", body: "Hi")

    get "/api/v1/public/discover/messages/#{answer.id}/speech", headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/public/discover/messages/#{elsewhere.id}/speech", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "says so when there is no speech endpoint, so the browser speaks instead" do
    allow(client).to receive(:speech_available?).and_return(false)
    get "/api/v1/public/discover/messages/#{question.id}/speech", headers: headers
    expect(response).to have_http_status(:service_unavailable)
  end
end
