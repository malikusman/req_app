# frozen_string_literal: true

require "rails_helper"

# An employee who answers a consultant's question used to get nothing back, while a
# casual "thanks!" got a warm companion reply -- the one message that took real
# effort was the one that looked ignored.
RSpec.describe "Consultant follow-up: acknowledging the employee's answer" do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) do
    create(:employee, company: company, phone_e164: "+971500900101", preferred_channel: "whatsapp")
  end
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed",
                          last_activity_at: 1.hour.ago)
  end
  let(:package) do
    DiscoveryPackage.create!(conversation: conversation, employee: employee, company: company,
                             version: 1, status: "ready", recommendation: "Automate the match.")
  end
  let(:requirement) do
    package.consultant_requirements.create!(
      consultant_user: consultant, employee: employee, company: company,
      statement: "Who signs off on a mismatch?", max_questions: 3
    )
  end
  let(:request) do
    ConsultantInfoRequest.create!(
      company: company, consultant_user: consultant, employee: employee, conversation: conversation,
      body: "Who signs off on a mismatch?", channel: "whatsapp",
      status: "awaiting_reply", sent_at: 1.hour.ago
    )
  end
  let!(:question) do
    package.discovery_followup_questions.create!(
      consultant_requirement: requirement, consultant_info_request: request,
      body: request.body, status: "sent", queue_position: 1
    )
  end

  def reply!(channel: "whatsapp", body: "Finance signs it off.")
    ConsultantFollowup::RecordReplyService.call(request: request, body: body, channel: channel)
  end

  def ack
    conversation.reload.messages
                .where(direction: "outbound")
                .find { |m| m.raw_payload["kind"] == "consultant_followup_ack" }
  end

  context "when the answer settles the requirement" do
    before do
      allow_any_instance_of(Langgraph::Client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => true, "missing_aspects" => [] })
    end

    it "tells the employee nothing further is needed" do
      reply!

      expect(ack).to be_present
      expect(ack.body).to match(/answers it.*Nothing further/i)
    end

    it "tracks the acknowledgement to the request, not as companion chatter" do
      reply!

      expect(ack.track).to eq("consultant_followup")
      expect(ack.track_ref).to eq(request)
      expect(ack.is_discovery_question).to be false
    end
  end

  context "when the requirement is only partly answered" do
    before do
      allow_any_instance_of(Langgraph::Client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => false, "missing_aspects" => ["Can they hold payment"] })
      allow_any_instance_of(Langgraph::Client).to receive(:draft_requirement_questions!)
        .and_return({ "questions" => [{ "body" => "Can they hold the payment?" }] })
    end

    it "does not promise that nothing further is needed" do
      reply!

      # Claiming "nothing further" here would be a lie -- the consultant may well
      # ask again, and the requirement is still open.
      expect(ack.body).to match(/one more quick question/i)
      expect(ack.body).not_to match(/nothing further/i)
    end
  end

  context "when there is no requirement behind the question" do
    let!(:question) { nil }

    it "confirms the answer was passed on without claiming an outcome" do
      reply!

      expect(ack.body).to match(/passed that on/i)
    end
  end

  context "channel" do
    it "answers a WhatsApp reply over WhatsApp" do
      allow_any_instance_of(Langgraph::Client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => true, "missing_aspects" => [] })
      client = instance_double(Whatsapp::MetaClient, configured?: true)
      allow(Whatsapp::MetaClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_text).and_return({ "messages" => [{ "id" => "wamid.ack" }] })

      reply!

      expect(client).to have_received(:send_text).with(hash_including(to: "+971500900101"))
      expect(ack.external_id).to eq("wamid.ack")
    end

    it "does not send a WhatsApp message for a web reply, only threads it" do
      allow_any_instance_of(Langgraph::Client).to receive(:evaluate_requirement!)
        .and_return({ "satisfied" => true, "missing_aspects" => [] })
      client = instance_double(Whatsapp::MetaClient, configured?: true)
      allow(Whatsapp::MetaClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_text)

      reply!(channel: "web")

      expect(client).not_to have_received(:send_text)
      expect(ack.channel).to eq("web")
    end
  end

  it "still records the reply when acknowledging fails" do
    allow_any_instance_of(Langgraph::Client).to receive(:evaluate_requirement!)
      .and_return({ "satisfied" => true, "missing_aspects" => [] })
    allow(Whatsapp::MetaClient).to receive(:new).and_raise(StandardError, "meta down")

    expect { reply! }.not_to raise_error
    expect(request.reload.status).to eq("replied")
    expect(conversation.messages.where(direction: "inbound").last.body).to eq("Finance signs it off.")
  end
end
