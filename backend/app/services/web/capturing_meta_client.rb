# frozen_string_literal: true

module Web
  # Stand-in Meta client that records outbound copy instead of sending WhatsApp messages.
  class CapturingMetaClient
    attr_reader :sent_messages

    def initialize
      @sent_messages = []
    end

    def configured?
      false
    end

    def send_text(to:, body:)
      @sent_messages << body.to_s
      { "success" => true, "captured" => true }
    end

    def send_typing_on(message_id:)
      { "success" => false, "skipped" => "web" }
    end
  end
end
