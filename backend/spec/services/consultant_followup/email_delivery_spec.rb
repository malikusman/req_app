# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant follow-up email delivery" do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) do
    # preferred_channel is whatsapp | web | both — "web" means a browser user.
    create(:employee, company: company, email: "layla@acme.test", preferred_channel: "web")
  end
  let!(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed")
  end

  def send_followup(**kwargs)
    ConsultantFollowup::SendService.call(
      consultant: consultant, employee: employee, body: "Which system holds the approval?", **kwargs
    )
  end

  describe "channel selection" do
    it "emails a browser-first employee" do
      result = send_followup

      expect(result[:request].channel).to eq("email")
      expect(result[:request].email_sent_at).to be_present
    end

    it "lets the caller override it" do
      expect(send_followup(channel: "whatsapp")[:request].channel).to eq("whatsapp")
    end

    it "falls back to whatsapp when a browser-first employee has no email" do
      employee.update!(email: nil, preferred_channel: "web")

      # Asking on a channel the employee has no address for is worse than asking on
      # their second choice.
      expect(send_followup[:request].channel).to eq("whatsapp")
    end

    it "always has whatsapp available as a fallback" do
      # employees.phone_e164 is NOT NULL and validated present, so there is always a
      # phone to fall back to. The Undeliverable guard in resolve_channel is
      # defensive against that invariant being relaxed, not a reachable path today.
      expect { employee.update!(phone_e164: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "the emailed question" do
    it "mails the employee a reply link and stores only the digest" do
      expect { send_followup }
        .to have_enqueued_mail(ConsultantFollowupMailer, :question_email)

      request = ConsultantInfoRequest.last
      expect(request.reply_token_digest).to be_present
      # The raw token exists only in the email — a leaked database cannot replay it.
      expect(request.reply_token_digest.length).to eq(64)
    end

    it "records the question in the employee's own thread" do
      result = send_followup

      message = result[:message]
      expect(message.direction).to eq("outbound")
      expect(message.track).to eq("consultant_followup")
      expect(message.track_ref).to eq(result[:request])
      # Visible in the web thread, which is where they will answer.
      expect(conversation.messages.employee_visible).to include(message)
    end

    it "marks the request awaiting a reply" do
      expect(send_followup[:request].status).to eq("awaiting_reply")
    end
  end

  describe "resolving a reply token" do
    it "finds the request by its raw token" do
      send_followup
      request = ConsultantInfoRequest.last
      raw = request.mint_reply_token!

      expect(ConsultantInfoRequest.find_by_reply_token(raw)).to eq(request)
    end

    it "returns nothing for a wrong or blank token" do
      send_followup

      expect(ConsultantInfoRequest.find_by_reply_token("nope")).to be_nil
      expect(ConsultantInfoRequest.find_by_reply_token(nil)).to be_nil
    end
  end

  describe "recording a reply, whatever channel it arrives on" do
    let(:request) { send_followup[:request] }

    it "lands an emailed answer in the thread and closes the request" do
      message = ConsultantFollowup::RecordReplyService.call(
        request: request, body: "SAP is the record.", channel: "email"
      )

      expect(request.reload.status).to eq("replied")
      expect(request.consultant_info_replies.count).to eq(1)
      expect(message.track).to eq("consultant_followup")
      expect(message.direction).to eq("inbound")
      expect(message.channel).to eq("web")
    end

    it "advances the consultant's requirement loop" do
      package = DiscoveryPackage.create!(
        conversation: conversation, employee: employee, company: company, version: 1, status: "ready"
      )
      requirement = ConsultantRequirement.create!(
        consultant_user: consultant, discovery_package: package, employee: employee,
        company: company, statement: "Which system is the record?", max_questions: 3
      )
      question = package.discovery_followup_questions.create!(
        consultant_requirement: requirement, body: "Which system?", status: "sent",
        queue_position: 1, consultant_info_request: request
      )
      allow_any_instance_of(Langgraph::Client)
        .to receive(:evaluate_requirement!).and_return({ "satisfied" => true, "missing_aspects" => [] })

      ConsultantFollowup::RecordReplyService.call(
        request: request, body: "SAP is the record.", channel: "email"
      )

      # Without this an emailed answer would leave the consultant's need open even
      # though the employee had answered it.
      expect(question.reload.status).to eq("answered")
      expect(requirement.reload).to be_satisfied
    end

    it "rejects an empty reply" do
      expect do
        ConsultantFollowup::RecordReplyService.call(request: request, body: "  ", channel: "email")
      end.to raise_error(ArgumentError)
    end
  end
end
