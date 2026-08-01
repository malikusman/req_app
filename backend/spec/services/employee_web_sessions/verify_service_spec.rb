# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmployeeWebSessions::VerifyService do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, participation_status: "invited", onboarding_step: "awaiting_consent",
                      display_name: "Sam", verified_at: Time.current)
  end
  let!(:consent) do
    ConsentTextVersion.create!(
      version: "v1-test",
      locale: "en",
      body: "Reply YES to continue.",
      confirmation_keywords: %w[YES],
      active: true
    )
  end
  let(:plain_token) { SecureRandom.urlsafe_base64(32) }
  let!(:session) do
    create(:employee_web_session, employee: employee, company: company,
                                  token_digest: EmployeeWebSessions::TokenDigest.digest(plain_token))
  end

  before { create(:discovery_playbook, department: employee.department) }

  describe ".call" do
    it "starts from link possession, issues JWT, and bootstraps consent" do
      result = described_class.call(token: plain_token, ip_address: "127.0.0.1")

      expect(result[:token]).to be_present
      payload = JsonWebToken.decode(result[:token])
      expect(payload[:aud]).to eq("employee_web")
      expect(payload[:employee_id]).to eq(employee.id)

      employee.reload
      expect(employee.onboarding_step).to eq("awaiting_consent")
      expect(session.reload.verified_at).to be_present

      outbound = result[:messages].find { |m| m[:direction] == "outbound" }
      expect(outbound[:body]).to include("YES")
    end

    it "rejects reuse of an already started link" do
      described_class.call(token: plain_token, ip_address: "127.0.0.1")

      expect {
        described_class.call(token: plain_token, ip_address: "127.0.0.1")
      }.to raise_error(described_class::AlreadyStarted)
    end

    it "rate limits repeated attempts on a used link" do
      described_class.call(token: plain_token, ip_address: "10.0.0.1")

      4.times do
        expect {
          described_class.call(token: plain_token, ip_address: "10.0.0.1")
        }.to raise_error(described_class::AlreadyStarted)
      end

      expect {
        described_class.call(token: plain_token, ip_address: "10.0.0.1")
      }.to raise_error(described_class::RateLimited)
    end
  end
end

RSpec.describe Discovery::DeliverReply do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, status: "discovery", question_count: 1) }

  it "persists web channel outbound messages without WhatsApp delivery" do
    client = instance_double(Whatsapp::MetaClient, configured?: true)
    allow(client).to receive(:send_text)

    message = described_class.call(
      conversation: conversation,
      employee: employee,
      result: { "assistant_message" => "What tools do you use?", "completed" => false },
      channel: :web,
      client: client
    )

    expect(message.channel).to eq("web")
    expect(client).not_to have_received(:send_text)
  end
end
