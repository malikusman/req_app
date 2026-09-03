# frozen_string_literal: true

require "rails_helper"

# Covers the gap this closes: outside the 24h WhatsApp session window, a
# consultant's follow-up used to reach the employee as a generic "we'll be in
# touch" template with the real question left undelivered -- their first reply
# would then be misattributed as the answer to a question they never saw.
# Now the template carries the question itself, so delivery is a single message
# regardless of window state, matching the in-window free-text path exactly.
RSpec.describe "Consultant follow-up: WhatsApp template carries the real question" do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) do
    create(:employee, company: company, phone_e164: "+971500900101", preferred_channel: "whatsapp")
  end
  let!(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          last_activity_at: last_activity)
  end
  let(:client) { instance_double(Whatsapp::MetaClient, configured?: true) }

  before do
    allow(Whatsapp::MetaClient).to receive(:new).and_return(client)
    allow(client).to receive(:send_text).and_return({ "messages" => [{ "id" => "wamid.1" }] })
    allow(client).to receive(:send_consultant_followup_template)
      .and_return({ "messages" => [{ "id" => "wamid.2" }] })
  end

  def send_followup
    ConsultantFollowup::SendService.call(
      consultant: consultant, employee: employee,
      body: "Who signs off on a mismatched PI, and can they hold the payment?"
    )
  end

  context "outside the 24h session window" do
    let(:last_activity) { 30.hours.ago }

    it "sends the template with the real question as the third variable" do
      send_followup

      expect(client).to have_received(:send_consultant_followup_template).with(
        to: "+971500900101",
        employee_name: employee.display_name || "there",
        company_name: company.display_name || company.name,
        question: "Who signs off on a mismatched PI, and can they hold the payment?"
      )
    end

    it "does not use plain text, which WhatsApp would reject outside the window" do
      send_followup

      expect(client).not_to have_received(:send_text)
    end
  end

  context "inside the 24h session window" do
    let(:last_activity) { 2.hours.ago }

    it "sends free text directly rather than going through a template" do
      send_followup

      expect(client).to have_received(:send_text).with(
        to: "+971500900101",
        body: "Who signs off on a mismatched PI, and can they hold the payment?"
      )
      expect(client).not_to have_received(:send_consultant_followup_template)
    end
  end
end
