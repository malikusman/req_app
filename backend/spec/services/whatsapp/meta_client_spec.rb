# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::MetaClient do
  describe "#send_consultant_followup_template" do
    let(:client) { described_class.new }

    before do
      allow(client).to receive(:configured?).and_return(true)
      allow(client).to receive(:post_messages)
    end

    it "sends the actual question as the third body variable, not a generic nudge" do
      client.send_consultant_followup_template(
        to: "+971500900101", employee_name: "Fatima", company_name: "Nimbus Trading",
        question: "Who signs off on a mismatched PI?"
      )

      expect(client).to have_received(:post_messages) do |payload|
        params = payload[:template][:components].first[:parameters]
        expect(params.map { |p| p[:text] }).to eq(
          ["Fatima", "Nimbus Trading", "Who signs off on a mismatched PI?"]
        )
      end
    end

    it "strips newlines and collapses runs of whitespace, which WhatsApp template params reject" do
      client.send_consultant_followup_template(
        to: "+971500900101", employee_name: "Fatima", company_name: "Nimbus",
        question: "Who   signs off\non a mismatched PI?  "
      )

      expect(client).to have_received(:post_messages) do |payload|
        params = payload[:template][:components].first[:parameters]
        expect(params.last[:text]).to eq("Who signs off on a mismatched PI?")
      end
    end

    it "reads the template name from ENV, defaulting to the consultant-branded name" do
      client.send_consultant_followup_template(
        to: "+971500900101", employee_name: "Fatima", company_name: "Nimbus", question: "Who signs off?"
      )

      expect(client).to have_received(:post_messages) do |payload|
        expect(payload[:template][:name]).to eq("consultant_followup_reopen")
      end
    end
  end
end
