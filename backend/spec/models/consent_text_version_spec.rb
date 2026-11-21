# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261121100000_add_channel_neutral_consent_text_version")

# Web and WhatsApp interviews send the same consent text, so it must not name a
# channel; Arabic-speaking employees get their own text and can agree in Arabic.
RSpec.describe "Channel-neutral consent text" do
  let(:texts) { AddChannelNeutralConsentTextVersion::TEXTS }

  it "names no channel and keeps the way to opt out in every language" do
    expect(texts.keys).to contain_exactly("en", "ar", "es")
    texts.each_value do |attrs|
      expect(attrs[:body]).not_to match(/whatsapp|واتساب/i)
      expect(attrs[:body]).to include("STOP")
    end
  end

  it "becomes the only active text for each language" do
    ConsentTextVersion.create!(version: "2026-06-20", locale: "en", active: true,
                               confirmation_keywords: %w[YES], body: "Old text via WhatsApp")
    ActiveRecord::Migration.suppress_messages { AddChannelNeutralConsentTextVersion.new.up }

    %w[en ar es].each do |locale|
      expect(ConsentTextVersion.active_for(locale).pluck(:version)).to eq([AddChannelNeutralConsentTextVersion::VERSION])
    end
  end

  it "accepts an Arabic yes from an Arabic-speaking employee" do
    ActiveRecord::Migration.suppress_messages { AddChannelNeutralConsentTextVersion.new.up }
    company = create(:company, settings: { "discovery_profiling_enabled" => true })
    employee = create(:employee, company: company, display_name: "Sara", preferred_language: "ar",
                                 participation_status: "invited", onboarding_step: "awaiting_consent",
                                 invited_at: Time.current, verified_at: Time.current)
    conversation = create(:conversation, employee: employee, company: company, status: "onboarding")
    allow(Subscriptions::ConversationLimitEnforcer).to receive(:can_start_discovery?).and_return(true)
    allow(Subscriptions::ConversationLimitEnforcer).to receive(:record_discovery_started!)
    client = instance_double(Whatsapp::MetaClient, configured?: false)
    handler = Whatsapp::OnboardingHandler.new(employee: employee, conversation: conversation, client: client)

    handler.handle_inbound_text("مرحبا")
    expect(conversation.messages.where(direction: "outbound").last.body).to include("نعم")

    handler.handle_inbound_text("نعم")
    expect(employee.reload.consent_given_at).to be_present
  end
end
