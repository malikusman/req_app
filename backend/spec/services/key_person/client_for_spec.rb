# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson do
  let(:company) { create(:company) }

  it "uses the model by default" do
    expect(described_class.client_for(company)).to be_a(Openai::Client)
  end

  it "uses scripted replies for a company set to them, outside production" do
    company.update!(settings: Company::DEFAULT_SETTINGS.merge("key_person_scripted_replies" => true))
    expect(described_class.client_for(company)).to be_a(KeyPerson::ScriptedClient)
  end

  it "never uses scripted replies in production" do
    company.update!(settings: Company::DEFAULT_SETTINGS.merge("key_person_scripted_replies" => true))
    allow(Rails.env).to receive(:production?).and_return(true)

    expect(described_class.client_for(company)).to be_a(Openai::Client)
    expect { KeyPerson::ScriptedClient.new }.to raise_error(/development and tests only/)
  end
end
