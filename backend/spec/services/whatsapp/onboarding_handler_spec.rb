# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::OnboardingHandler do
  let(:company) { create(:company) }
  let(:employee) do
    company.employees.create!(
      phone_e164: "+15552223333",
      display_name: nil,
      participation_status: "invited",
      onboarding_step: "awaiting_name",
      invited_at: Time.current
    )
  end
  let(:conversation) do
    employee.conversations.create!(company: company, status: "onboarding", started_at: Time.current)
  end
  let(:client) { instance_double(Whatsapp::MetaClient, configured?: false, send_text: true) }

  before do
    company.update_column(:join_code, "XY99Z")
    ConsentTextVersion.find_or_create_by!(version: "v1-test", locale: "en") do |c|
      c.body = "Reply YES to participate."
      c.confirmation_keywords = ["YES"]
      c.active = true
    end
  end

  it "skips personal access code and moves invited employee to consent after name" do
    handler = described_class.new(employee: employee, conversation: conversation, client: client)
    handler.handle_inbound_text("Alex")

    expect(employee.reload.onboarding_step).to eq("awaiting_consent")
    expect(employee.display_name).to eq("Alex")
  end
end
