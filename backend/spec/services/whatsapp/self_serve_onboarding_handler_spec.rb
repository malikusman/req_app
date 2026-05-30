# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::SelfServeOnboardingHandler do
  let(:company) { create(:company) }
  let(:phone) { "+15550001111" }
  let(:client) { instance_double(Whatsapp::MetaClient, configured?: false, send_text: true) }

  before do
    Whatsapp::SelfServeOnboardingHandler::FALLBACK_STORE.clear
    company.update_column(:join_code, "AB12C") if company.join_code != "AB12C"
    ConsentTextVersion.find_or_create_by!(version: "2026-05-01", locale: "en") do |c|
      c.body = "Reply YES to participate."
      c.confirmation_keywords = ["YES"]
      c.active = true
    end
  end

  def self_serve_state(phone)
    Whatsapp::SelfServeOnboardingHandler::FALLBACK_STORE["whatsapp/self_serve/#{phone}"]
  end

  it "prompts for company code on hello" do
    described_class.new(phone: phone, client: client).handle_inbound_text("hello")
    expect(Rails.cache.read("whatsapp/self_serve/#{phone}")).to be_nil
  end

  it "accepts valid company code and asks for name" do
    described_class.new(phone: phone, client: client).handle_inbound_text(company.join_code)

    state = self_serve_state(phone)
    expect(state["step"]).to eq("awaiting_name")
    expect(state["company_id"]).to eq(company.id)
  end

  it "creates walk-in employee after name" do
    handler = described_class.new(phone: phone, client: client)
    handler.handle_inbound_text(company.join_code)
    expect {
      handler.handle_inbound_text("Jordan Lee")
    }.to change(Employee, :count).by(1)

    employee = Employee.find_by(phone_e164: phone)
    expect(employee.company_id).to eq(company.id)
    expect(employee.display_name).to eq("Jordan Lee")
    expect(employee.invited_at).to be_nil
  end

  it "links email-only invited employee" do
    invited = company.employees.create!(
      email: "sam@example.com",
      display_name: "Sam",
      participation_status: "invited",
      onboarding_step: "awaiting_name",
      invited_at: Time.current
    )

    handler = described_class.new(phone: phone, client: client)
    handler.handle_inbound_text(company.join_code)
    handler.handle_inbound_text("sam@example.com")

    expect(invited.reload.phone_e164).to eq(phone)
    expect(Employee.where(phone_e164: phone).count).to eq(1)
  end
end
