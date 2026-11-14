# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Transcribing a spoken answer" do
  let(:company) { create(:company, locale: "en") }
  let(:employee) { create(:employee, company: company, preferred_language: nil) }
  let(:conversation) { create(:conversation, company: company, employee: employee, status: "discovery") }
  let(:message) { conversation.messages.create!(direction: "inbound", channel: "web", message_type: "audio") }

  def attachment(mime)
    MediaAttachment.create!(message: message, company: company, employee: employee, conversation: conversation,
                            attachment_type: "audio", mime_type: mime, status: "pending", storage_key: "k")
  end

  it "keeps the recording's real format, which the transcription model reads from the extension" do
    service = ->(mime) { Multimodal::ProcessMediaService.new(attachment(mime).id).send(:extension_for_type) }
    expect(service.call("audio/webm")).to eq(".webm")
    expect(service.call("audio/mp4")).to eq(".m4a")
    expect(service.call("audio/ogg")).to eq(".ogg")
  end

  it "lets the model detect the language when the person's is not known" do
    client = instance_double(Openai::Client)
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(client).to receive(:transcribe_audio).and_return("كل صباح")

    Multimodal::UnderstandingService.call(attachment: attachment("audio/webm"), file_path: "/tmp/x.webm")

    expect(client).to have_received(:transcribe_audio).with(file_path: "/tmp/x.webm", language: nil)
  end
end
